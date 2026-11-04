# ClawLibrary

- [中文说明 / README_cn.md](./README_cn.md)

ClawLibrary is a 2D pixel-game-style control interface for OpenClaw.

It turns OpenClaw's generated assets, runtime activity, and assets related working state into a visual library interface that can be browsed, previewed, and monitored in real time.

Overall, it aims to feel more like a living pixel archive than a plain folder tree.

![ClawLibrary preview screenshot](./public/ClawLibrary_preview.jpg)

## Highlights

- classify, index, and manage many different asset types produced by OpenClaw
- open and preview those assets directly inside the interface
- see what OpenClaw is currently accessing, using, or processing
- connect runtime behavior to concrete asset rooms instead of raw folders
- present the whole workflow in a more approachable 2D pixel-game UI
- keep the art layer replaceable so visuals can evolve independently from the logic layer

## What It Does

ClawLibrary maps OpenClaw-related resources into visual rooms such as:

![ClawLibrary preview animation](./public/ClawLibrary_preview-6s.gif)

- document archive
- image atelier
- memory vault
- skill forge
- interface gateway
- code lab
- scheduler
- alarm board
- runtime monitor
- queue hub
- break room

The interface is mainly designed to answer two questions:

1. What assets already exist?
2. What is OpenClaw doing with them right now?



## Core Features

- room routing driven by live OpenClaw activity
- asset partitions aligned to OpenClaw resource types
- direct in-panel asset browsing and preview
- actor movement linked to room state
- debug overlays for mapping and route inspection
- replaceable pixel-art scene assets

## Installation

### Easiest Setup: Send the Repo to OpenClaw

If the other person already has OpenClaw installed, the easiest path is to send the repository URL to their OpenClaw and let it install and launch the project automatically.

You can send a prompt like this:

```text
Please install and launch this repository: clone https://github.com/shengyu-meng/ClawLibrary, enter the project folder, run npm install, npm run validate, then start the dev server and tell me the final URL.
```

If you need LAN access, add a note asking OpenClaw to enable LAN access and report the LAN URL.

### Standard Local Setup

```bash
git clone https://github.com/shengyu-meng/ClawLibrary ClawLibrary
cd ClawLibrary
npm install
npm run validate
npm run dev
```

Then open:

- local only: `http://127.0.0.1:5173/`
- LAN mode if enabled: `http://<your-ip>:5173/`

The simplest way to start LAN mode is:

```bash
CLAWLIBRARY_SERVER_HOST=0.0.0.0 npm run dev
```

Use a password only for this mode:

- local-only `npm run dev` on `127.0.0.1` does not require a password
- LAN mode on `0.0.0.0` or another non-local host requires a password
- if `auth.password` / `CLAWLIBRARY_ACCESS_PASSWORD` is unset, startup will prompt for a per-process password
- for non-interactive launches, preconfigure `auth.password` or `CLAWLIBRARY_ACCESS_PASSWORD`

If your OpenClaw installation is not under the default path, the recommended way is to edit:

- `clawlibrary.config.json`

If you prefer environment-variable overrides, copy and fill:

```bash
cp .env.example .env
```

and set:

- `OPENCLAW_HOME`
- `OPENCLAW_WORKSPACE`

## Two isolated Nginx environments (temporary Linux container)

| Environment | Directory | Nginx URL (all IPv4 interfaces) | App upstream |
| --- | --- | --- | --- |
| dev | `~/ClawLibrary/dev` | `http://<container-host>:8081/` | `127.0.0.1:5181` (Vite dev) |
| prod | `~/ClawLibrary/prod` | `http://<container-host>:8082/` | `127.0.0.1:5182` (built Vite preview) |

Run from the source checkout on Linux with Bash, Node/npm, `setsid`, and Nginx installed. Preparation installs locked dependencies and builds each independent project copy. Both modes proxy the full application, including `/api/openclaw/*`; a static-only Nginx root would lose the telemetry API. Vite preview is suitable for this temporary container setup, not a hardened production backend.

```bash
# If outbound connectivity requires the provided proxy (keep loopback direct):
export HTTP_PROXY=http://192.168.5.140:7897 HTTPS_PROXY=http://192.168.5.140:7897
export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY"
export npm_config_proxy="$HTTP_PROXY" npm_config_https_proxy="$HTTPS_PROXY"
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
# Git invoked by the workspace daemon needs its own proxy setting:
git config --global http.https://github.com/.proxy "$HTTPS_PROXY"
# Install nginx with your Linux package manager first, if missing.
bash scripts/environments.sh prepare dev
bash scripts/environments.sh prepare prod
bash scripts/environments.sh start dev
bash scripts/environments.sh start prod
bash scripts/environments.sh test dev
bash scripts/environments.sh test prod
bash scripts/environments.sh status dev
bash scripts/environments.sh status prod
# Stop only the selected environment:
bash scripts/environments.sh stop dev
bash scripts/environments.sh stop prod
```

Each environment owns `runtime/nginx.conf`, `runtime/nginx.pid`, `runtime/app.pid`, and `runtime/logs/{app,access,error}.log`. Processes detach using `setsid` / Nginx daemon mode with persistent local logs; without a supervisor survival is best-effort and there is no automatic restart. Container deletion removes both environments. Nginx listens on `0.0.0.0:8081/8082`; upstreams remain loopback-only. Actual external reachability still depends on container networking and port publishing. Non-loopback requests require Basic authentication: username `admin`, a separately generated password per environment in `runtime/access-password` (read locally with `cat ~/ClawLibrary/dev/runtime/access-password`, or substitute `prod`). Redeployment migrates the legacy `clawlibrary` account to `admin` without changing its password hash or the password file. To migrate an existing environment without rebuilding or restarting, run `bash scripts/environment-auth.sh ~/ClawLibrary/dev/runtime` (substitute `prod` as needed); Nginx reads the updated credentials on subsequent requests. Never commit or publish that file. Loopback checks bypass authentication. Basic authentication over HTTP is not encrypted: use a trusted network or TLS/SSH tunnel; this does not configure Internet routing, TLS, or firewall rules. Nginx pins the upstream Host to localhost so Vite accepts external proxy requests.

Stop an environment before running `prepare` again to deploy updated source; preparation overwrites tracked project files but preserves runtime logs. Do not store credentials in deployed source: `.env`, Git metadata and developer `node_modules` are excluded from copying. Optional `CLAWLIBRARY_ENV_ROOT` changes the base directory (absolute, no spaces); `NGINX_BIN` selects the Nginx executable. The two environments have separate code/builds/processes, but by default read the same OpenClaw data; configure each copy's `clawlibrary.config.json` for different data sources if needed. Do not prepare from a deployed copy itself.

## Development Commands

```bash
npm run dev
npm run validate
npm run typecheck
npm run build
```

Optional QA commands:

```bash
npm run qa:movement
npm run qa:visual:baseline
npm run qa:visual
```

These QA commands generate local temporary artifacts. They currently write into `tmp/qa/` and are not meant to be part of the public repository.

## Runtime Model

ClawLibrary is driven by protocol-style data plus live telemetry:

- `src/data/map.logic.json` — room layout, anchors, walk graph, work zones
- `src/data/asset.manifest.json` — logical asset definitions
- `src/data/scene-art.manifest.json` — actor and scene art bindings
- `src/data/work-output.protocol.json` — work-state mapping and output semantics
- `scripts/openclaw-telemetry.mjs` — bridge from OpenClaw state into live museum signals

## Configuration

ClawLibrary now uses `clawlibrary.config.json` at the repository root as the public-facing config entry point.

Current config surface includes:

- `debug` — whether to show room anchors, route circles, and other debug overlays
- `host` — `127.0.0.1` for local-only access, `0.0.0.0` or a LAN IP for shared access
- `port` — dev server port
- `auth.password` — required whenever `host` is not local-only
- `auth.sessionTtlHours` — how long a successful password unlock stays valid
- `locale` — `en` or `zh`
- `defaultActorVariant` — choose the default actor skin

Default config file:

```json
{
  "openclaw": {
    "home": "",
    "workspace": ""
  },
  "server": {
    "host": "127.0.0.1",
    "port": 5173
  },
  "auth": {
    "password": "",
    "sessionTtlHours": 12
  },
  "ui": {
    "defaultLocale": "en",
    "showDebugToggle": false,
    "defaultDebugVisible": false,
    "showInfoToggle": true,
    "defaultInfoPanelVisible": true,
    "showThemeToggle": false
  },
  "actor": {
    "defaultVariantId": "capy-claw-emoji"
  },
  "telemetry": {
    "pollMs": 2500
  }
}
```

Supporting files:

- `.env.example` — optional environment-variable override example
- `scripts/clawlibrary-config.mjs` — shared config loader for config file + env overrides

Environment variable overrides:

- `CLAWLIBRARY_SERVER_HOST`
- `CLAWLIBRARY_SERVER_PORT`
- `CLAWLIBRARY_ACCESS_PASSWORD`
- `CLAWLIBRARY_SESSION_TTL_HOURS`

Security note:

- The bundled config now defaults to `127.0.0.1`.
- If you bind ClawLibrary to `0.0.0.0` or another non-local host, ClawLibrary uses `auth.password` / `CLAWLIBRARY_ACCESS_PASSWORD` first and otherwise prompts for a per-process password at startup.
- For non-interactive launches, preconfigure `auth.password` or `CLAWLIBRARY_ACCESS_PASSWORD` because no terminal prompt is available.

## OpenClaw Path Discovery

ClawLibrary does not hardcode a single machine path.

Current lookup strategy:

- read `clawlibrary.config.json` first
- override with `OPENCLAW_HOME` if provided
- override with `OPENCLAW_WORKSPACE` if provided
- if neither config nor env is set, fall back to the standard OpenClaw layout:
  - `~/.openclaw`
  - `~/.openclaw/workspace`

That means:

- standard OpenClaw installations should work out of the box
- custom installations can be supported through config or environment-variable overrides

## Open-Source Repository Guidance

A public release should mainly keep:

- runtime code
- required public assets
- installation commands
- configuration docs
- a few polished preview assets

Internal QA captures, prompt drafts, and iteration logs are usually better removed from the public release.

## License

Code is licensed under MIT:

- `/LICENSE`

Assets are licensed under CC BY-NC-SA 4.0:

- `/LICENSE-ASSETS.md`
- Non-commercial sharing, adaptation, and redistribution are allowed with attribution.
- If you redistribute adapted assets, you must keep them under the same license.
- For commercial use of this project, replace the included art assets with your own, or obtain separate permission.

## Acknowledgements

- This project is inspired by [Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI).
- Special thanks to [@simonxxooxxoo](https://github.com/simonxxooxxoo) and [@ringhyacinth](https://github.com/ringhyacinth).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=shengyu-meng/ClawLibrary&type=Date)](https://www.star-history.com/#shengyu-meng/ClawLibrary&Date)
