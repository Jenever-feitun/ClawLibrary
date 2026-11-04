#!/usr/bin/env bash
# Two independently managed ClawLibrary instances; authenticated external Nginx access.
set -euo pipefail
SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE=${CLAWLIBRARY_ENV_ROOT:-"$HOME/ClawLibrary"}
NGINX=${NGINX_BIN:-$(command -v nginx || true)}
[[ -n "$NGINX" ]] || NGINX=/usr/sbin/nginx
usage() { echo 'Usage: bash scripts/environments.sh {prepare|start|stop|status|test} {dev|prod}' >&2; exit 2; }
[[ $# == 2 ]] || usage
ACTION=$1
ENV=$2
case "$ENV" in
  dev) PORT=8081; UPSTREAM=5181 ;;
  prod) PORT=8082; UPSTREAM=5182 ;;
  *) usage ;;
esac
DIR="$BASE/$ENV"
# Nginx config interpolation deliberately accepts only simple absolute paths.
[[ "$DIR" == /* && "$DIR" != *[!a-zA-Z0-9_./-]* ]] || { echo 'Environment root must be an absolute path without spaces or special characters' >&2; exit 2; }
[[ "$SOURCE" != "$DIR" ]] || { echo 'Run from the source checkout, not a deployed copy' >&2; exit 2; }
[[ -x "$NGINX" ]] || { echo 'Install nginx first' >&2; exit 1; }
RUNTIME="$DIR/runtime"
alive() { [[ -s "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }
case "$ACTION" in
  prepare)
    if alive "$RUNTIME/nginx.pid" || alive "$RUNTIME/app.pid"; then
      echo 'Stop this environment before preparing it again' >&2; exit 1
    fi
    mkdir -p "$DIR" "$RUNTIME/logs" "$RUNTIME/client_temp" "$RUNTIME/proxy_temp" "$RUNTIME/fastcgi_temp" "$RUNTIME/uwsgi_temp" "$RUNTIME/scgi_temp"
    # No credentials, Git metadata, runtime logs or developer dependencies copied.
    tar -C "$SOURCE" --exclude=.git --exclude=node_modules --exclude=dist --exclude=tmp --exclude=./.env --exclude=./runtime -cf - . | tar -C "$DIR" -xf -
    (cd "$DIR" && npm ci --include=dev && npm run build)
    # Preserve passwords/hashes; migrate only the old Basic-auth username to admin.
    bash "$SOURCE/scripts/environment-auth.sh" "$RUNTIME"
    cat > "$RUNTIME/nginx.conf" <<CONF
worker_processes 1;
pid $RUNTIME/nginx.pid;
error_log $RUNTIME/logs/error.log;
events { worker_connections 256; }
http {
    access_log $RUNTIME/logs/access.log;
    client_body_temp_path $RUNTIME/client_temp;
    proxy_temp_path $RUNTIME/proxy_temp;
    fastcgi_temp_path $RUNTIME/fastcgi_temp;
    uwsgi_temp_path $RUNTIME/uwsgi_temp;
    scgi_temp_path $RUNTIME/scgi_temp;
    server {
        listen 0.0.0.0:$PORT;
        # Loopback checks remain direct; non-local requests require Basic auth.
        satisfy any;
        allow 127.0.0.1;
        deny all;
        auth_basic "ClawLibrary $ENV";
        auth_basic_user_file $RUNTIME/htpasswd;
        server_name localhost;
        location / {
            proxy_pass http://127.0.0.1:$UPSTREAM;
            proxy_set_header Host localhost;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 60s;
        }
    }
}
CONF
    "$NGINX" -t -p "$RUNTIME/" -c "$RUNTIME/nginx.conf"
    echo "Prepared $ENV: $DIR; nginx=$PORT upstream=$UPSTREAM"
    ;;
  start)
    [[ -f "$RUNTIME/nginx.conf" && -d "$DIR/node_modules" && -f "$DIR/dist/index.html" ]] || { echo 'Run prepare first' >&2; exit 1; }
    if alive "$RUNTIME/nginx.pid" || alive "$RUNTIME/app.pid"; then
      echo 'Environment already running (or partially running); use status/stop first' >&2; exit 1
    fi
    # Fail rather than silently choose a different port.
    node --input-type=module - "$PORT" "$UPSTREAM" <<'JS'
import net from 'node:net';
for (const port of process.argv.slice(2)) {
  await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(Number(port), port === process.argv[2] ? '0.0.0.0' : '127.0.0.1', () => server.close(resolve));
  });
}
JS
    "$NGINX" -t -p "$RUNTIME/" -c "$RUNTIME/nginx.conf"
    ARGS=(); [[ "$ENV" == prod ]] && ARGS=(preview)
    # setsid + closed stdin and durable logs detach from the invoking agent run.
    (cd "$DIR" && exec setsid env CLAWLIBRARY_SERVER_HOST=127.0.0.1 CLAWLIBRARY_SERVER_PORT="$UPSTREAM" node node_modules/vite/bin/vite.js "${ARGS[@]}" --host 127.0.0.1 --port "$UPSTREAM" --strictPort </dev/null >>"$RUNTIME/logs/app.log" 2>&1) &
    echo $! > "$RUNTIME/app.pid"
    cleanup() {
      if alive "$RUNTIME/app.pid"; then kill "$(cat "$RUNTIME/app.pid")"; fi
      rm -f "$RUNTIME/app.pid"
    }
    trap cleanup ERR
    # Bounded readiness check, not deferred scheduling.
    node --input-type=module - "$UPSTREAM" <<'JS'
const url = `http://127.0.0.1:${process.argv[2]}/`;
for (let i = 0; i < 60; i++) {
  try { const response = await fetch(url, {signal: AbortSignal.timeout(1000)}); if (response.ok) process.exit(0); } catch {}
  await new Promise(resolve => setTimeout(resolve, 250));
}
throw new Error(`Not ready: ${url}`);
JS
    "$NGINX" -p "$RUNTIME/" -c "$RUNTIME/nginx.conf"
    trap - ERR
    echo "$ENV ready: http://127.0.0.1:$PORT/ (nginx PID $(cat "$RUNTIME/nginx.pid"), app PID $(cat "$RUNTIME/app.pid"))"
    ;;
  stop)
    if alive "$RUNTIME/nginx.pid"; then "$NGINX" -p "$RUNTIME/" -c "$RUNTIME/nginx.conf" -s quit; fi
    if alive "$RUNTIME/app.pid"; then
      PID=$(cat "$RUNTIME/app.pid")
      # Refuse to signal a PID reused by an unrelated process.
      if [[ -r "/proc/$PID/cmdline" ]] && tr '\0' ' ' < "/proc/$PID/cmdline" | grep -q 'node_modules/vite/bin/vite.js'; then
        kill "$PID"
      else
        echo 'App PID does not identify Vite; refusing to signal it' >&2; exit 1
      fi
    fi
    rm -f "$RUNTIME/app.pid"
    ;;
  status)
    alive "$RUNTIME/nginx.pid" && echo "nginx running PID=$(cat "$RUNTIME/nginx.pid")" || { echo 'nginx stopped'; exit 1; }
    alive "$RUNTIME/app.pid" && echo "app running PID=$(cat "$RUNTIME/app.pid")" || { echo 'app stopped'; exit 1; }
    echo "http://127.0.0.1:$PORT/"
    ;;
  test)
    "$NGINX" -t -p "$RUNTIME/" -c "$RUNTIME/nginx.conf"
    node --input-type=module - "$PORT" <<'JS'
import assert from 'node:assert/strict';
const base = `http://127.0.0.1:${process.argv[2]}`;
const page = await fetch(base, {signal: AbortSignal.timeout(10000)});
assert.equal(page.status, 200);
assert.match(await page.text(), /<html/i);
const api = await fetch(`${base}/api/openclaw/snapshot`, {signal: AbortSignal.timeout(30000)});
assert.equal(api.status, 200);
assert.match(api.headers.get('content-type'), /json/);
assert.equal(typeof await api.json(), 'object');
console.log('PASS: HTML and telemetry API through nginx');
JS
    ;;
  *) usage ;;
esac
