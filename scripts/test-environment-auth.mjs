import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';

const root = path.resolve(import.meta.dirname, '..');
await fs.mkdir(path.join(root, 'tmp'), { recursive: true });
const fixture = await fs.mkdtemp(path.join(root, 'tmp', 'auth-'));
const runtime = path.join(fixture, 'runtime');
const password = 'test-only-owner-password';
const nginx = process.env.NGINX_BIN || '/usr/sbin/nginx';
let server;
function migrate(ok = true) {
  const result = spawnSync('bash', [path.join(root, 'scripts/environment-auth.sh'), runtime], { encoding: 'utf8' });
  assert.equal(result.status === 0, ok, result.stderr);
}
const request = (port, username, localAddress = '127.0.0.2') => new Promise((resolve, reject) => {
  const req = http.get({ host: '127.0.0.1', port, localAddress,
    headers: username ? { Authorization: `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}` } : {}
  }, res => { res.resume(); res.on('end', () => resolve(res.statusCode)); });
  req.setTimeout(3000, () => req.destroy(new Error('HTTP timeout')));
  req.on('error', reject);
});
try {
  migrate();
  const fresh = await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8');
  assert.match(fresh, /^admin:\$apr1\$/);
  const generated = await fs.readFile(path.join(runtime, 'access-password'), 'utf8');
  assert.match(generated, /^[a-f0-9]{36}\n$/);
  migrate();
  assert.equal(await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8'), fresh);
  assert.equal(await fs.readFile(path.join(runtime, 'access-password'), 'utf8'), generated);

  // Existing custom password without a hash must not be regenerated.
  await fs.unlink(path.join(runtime, 'htpasswd'));
  await fs.writeFile(path.join(runtime, 'access-password'), password + '\n');
  migrate();
  const customized = await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8');
  const hash = customized.trim().split(':')[1];
  const verify = spawnSync('openssl', ['passwd', '-apr1', '-salt', hash.split('$')[2], '-stdin'], { input: password + '\n', encoding: 'utf8' });
  assert.equal(verify.stdout.trim(), hash);
  await fs.writeFile(path.join(runtime, 'htpasswd'), `clawlibrary:${hash}\n`);
  migrate();
  assert.equal(await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8'), customized);
  assert.equal(await fs.readFile(path.join(runtime, 'access-password'), 'utf8'), password + '\n');
  assert.equal((await fs.stat(path.join(runtime, 'htpasswd'))).mode & 0o777, 0o600);
  migrate();
  assert.equal(await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8'), customized);
  // Hash-only deployments must not acquire a replacement password file.
  await fs.unlink(path.join(runtime, 'access-password'));
  migrate();
  await assert.rejects(fs.access(path.join(runtime, 'access-password')));
  assert.equal(await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8'), customized);
  for (const invalid of [`other:${hash}\n`, `admin:${hash}\nclawlibrary:${hash}\n`, 'admin:\n']) {
    await fs.writeFile(path.join(runtime, 'htpasswd'), invalid);
    migrate(false);
    assert.equal(await fs.readFile(path.join(runtime, 'htpasswd'), 'utf8'), invalid);
  }
  await fs.writeFile(path.join(runtime, 'htpasswd'), customized, { mode: 0o600 });
  const listener = net.createServer();
  listener.listen(0, '127.0.0.1');
  await once(listener, 'listening');
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  await fs.writeFile(path.join(fixture, 'index.html'), 'authenticated fixture');
  const config = path.join(fixture, 'nginx.conf');
  await fs.writeFile(config, `daemon off;
master_process off;
pid ${fixture}/nginx.pid;
error_log stderr;
events { worker_connections 32; }
http {
  client_body_temp_path ${fixture}/client_temp;
  proxy_temp_path ${fixture}/proxy_temp;
  fastcgi_temp_path ${fixture}/fastcgi_temp;
  uwsgi_temp_path ${fixture}/uwsgi_temp;
  scgi_temp_path ${fixture}/scgi_temp;
  access_log off;
  server {
    listen 127.0.0.1:${port};
    satisfy any;
    allow 127.0.0.1;
    deny all;
    auth_basic "test";
    auth_basic_user_file ${runtime}/htpasswd;
    root ${fixture};
  }
}
`);
  let logs = '';
  server = spawn(nginx, ['-p', fixture + '/', '-c', config], { stdio: ['ignore', 'ignore', 'pipe'] });
  server.stderr.on('data', chunk => { logs += chunk; });
  let ready = false;
  for (let attempt = 0; attempt < 50; attempt++) {
    try { assert.equal(await request(port, null, '127.0.0.1'), 200); ready = true; break; } catch {}
    if (server.exitCode !== null) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.ok(ready, logs);
  assert.equal(await request(port), 401);
  assert.equal(await request(port, 'admin'), 200);
  assert.equal(await request(port, 'clawlibrary'), 401);
  assert.equal(await request(port, 'incorrect'), 401);
  console.log('PASS: generation, custom password preservation, hash migration, idempotence, permissions, invalid-file protection; real Nginx: admin 200, legacy/no auth 401, local bypass 200');
} finally {
  if (server && server.exitCode === null) {
    const exited = once(server, 'exit');
    server.kill('SIGTERM');
    await exited;
  }
  await fs.rm(fixture, { recursive: true, force: true });
}
