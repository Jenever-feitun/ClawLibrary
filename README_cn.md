# 龙虾图书馆 / ClawLibrary

- [English README / README.md](./README.md)

龙虾图书馆是一个面向 OpenClaw 的 2D 像素游戏风资产控制室。

它把 OpenClaw 生成出来的大量资产、运行中的访问行为、以及不同资源房间之间的关系，变成一个可浏览、可预览、可实时观察的像素游戏风图书馆界面。

![龙虾图书馆预览截图](./public/ClawLibrary_preview.jpg)

## 项目亮点

- 对 OpenClaw 生成的不同类型资产做分类、索引和管理
- 可以直接在界面里打开和预览这些资产
- 可以实时看到 OpenClaw 正在访问、使用或处理哪一类资源
- 可以把运行状态和具体资产房间关联起来，不再只是看一堆文件夹
- 用更友好的 2D 像素游戏界面呈现整个工作流
- 美术资源可以替换，逻辑层和视觉层可以分离演进


## 它在做什么

龙虾图书馆 / ClawLibrary 会把 OpenClaw 相关资源映射到不同房间，例如：

![龙虾图书馆预览动图](./public/ClawLibrary_preview-6s.gif)


- 文档归档
- 图像工坊
- 记忆库
- 技能锻炉
- 接口网关
- 代码实验室
- 调度台
- 报警台
- 运行监控
- 队列中枢
- 休息室

整个界面主要回答两个问题：

1. 现在已经有哪些资产？
2. OpenClaw 正在对这些资产做什么？

## 核心功能

- 由 OpenClaw 实时活动驱动的房间路由
- 按 OpenClaw 资源类型划分资产分区
- 可以直接在面板内浏览和预览资产
- 角色移动与房间状态联动
- 提供用于映射和路径检查的调试叠层
- 可替换的像素场景美术资源



## 安装

### 最简单的方法：直接发给 OpenClaw 让它安装

如果对方已经装好了 OpenClaw，最简单的方法就是把仓库地址直接发给它的 OpenClaw，让它帮忙完成安装和启动。

你可以直接发这样一句话：

```text
请帮我安装并启动这个仓库：克隆 https://github.com/shengyu-meng/ClawLibrary 到本地，进入项目目录执行 npm install、npm run validate，然后启动开发服务，并把最终访问地址告诉我。
```

如果你需要局域网访问，可以在这句提示里补一句，要求 OpenClaw 启用局域网访问并返回局域网地址。

### 标准本地启动

```bash
git clone https://github.com/shengyu-meng/ClawLibrary ClawLibrary
cd ClawLibrary
npm install
npm run validate
npm run dev
```

启动后访问：

- 本机访问：`http://127.0.0.1:5173/`
- 如果启用了局域网监听：`http://<你的局域网IP>:5173/`

最简单的局域网启动方式：

```bash
CLAWLIBRARY_SERVER_HOST=0.0.0.0 npm run dev
```

只有这种非本机监听模式需要密码：

- 本机模式 `npm run dev` 监听 `127.0.0.1` 时不需要密码
- 局域网模式监听 `0.0.0.0` 或其他非本机地址时需要密码
- 如果没有预先设置 `auth.password` / `CLAWLIBRARY_ACCESS_PASSWORD`，启动时会提示你为当前进程输入一次密码
- 如果是非交互式启动，请提前配置 `auth.password` 或 `CLAWLIBRARY_ACCESS_PASSWORD`

如果你的 OpenClaw 不在默认路径，优先推荐直接修改：

- `clawlibrary.config.json`

如果你更习惯用环境变量覆盖，也可以复制并填写：

```bash
cp .env.example .env
```

然后设置：

- `OPENCLAW_HOME`
- `OPENCLAW_WORKSPACE`

## 临时 Linux 容器双环境

| 环境 | 项目目录 | Nginx 访问地址（全部 IPv4 网卡） | 应用上游 |
| --- | --- | --- | --- |
| dev | `~/ClawLibrary/dev` | `http://<容器可达地址>:8081/` | `127.0.0.1:5181`，Vite dev |
| prod | `~/ClawLibrary/prod` | `http://<容器可达地址>:8082/` | `127.0.0.1:5182`，构建产物 Vite preview |

依赖 Linux、Bash、Node/npm、`setsid`、Nginx。必须从源码检出目录执行：

```bash
# 需要代理时使用；本机请求不走代理
export HTTP_PROXY=http://192.168.5.140:7897 HTTPS_PROXY=http://192.168.5.140:7897
export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY"
export npm_config_proxy="$HTTP_PROXY" npm_config_https_proxy="$HTTPS_PROXY"
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
# 工作区 daemon 执行 Git 时需要单独配置 Git 代理
git config --global http.https://github.com/.proxy "$HTTPS_PROXY"
# 先通过系统包管理器安装 nginx，再初始化两套独立源码/依赖/构建
bash scripts/environments.sh prepare dev
bash scripts/environments.sh prepare prod
bash scripts/environments.sh start dev
bash scripts/environments.sh start prod
bash scripts/environments.sh test dev
bash scripts/environments.sh test prod
bash scripts/environments.sh status dev
bash scripts/environments.sh status prod
# 按需独立停止
bash scripts/environments.sh stop dev
bash scripts/environments.sh stop prod
```

Nginx 转发完整应用，包括 `/api/openclaw/*`，避免仅托管静态文件导致遥测接口失效。prod 使用构建产物及 Vite preview，适用于此次临时容器，不是加固后的生产后端。

每个环境独立记录 `runtime/nginx.conf`、`runtime/nginx.pid`、`runtime/app.pid` 以及 `runtime/logs/{app,access,error}.log`。应用通过 `setsid` 脱离当前任务，Nginx 自身 daemon 化；无进程监督器，仅尽力维持运行，不提供崩溃自动重启。容器销毁后服务及本地文件不保留。

Nginx 监听 `0.0.0.0:8081/8082`，上游仍仅监听 loopback；外部能否访问取决于容器网络及端口映射，不代表已配置公网路由、防火墙或 TLS。非本机请求需要 Basic 认证：用户名 `admin`，每套环境独立生成密码，保存在 `runtime/access-password`，可在容器中执行 `cat ~/ClawLibrary/dev/runtime/access-password` 查看（prod 同理）。重新部署时会将旧账号 `clawlibrary` 迁移为 `admin`，保留原密码哈希和密码文件。已有环境也可执行 `bash scripts/environment-auth.sh ~/ClawLibrary/dev/runtime`（prod 同理）单独迁移，无需重新构建或重启，Nginx 在后续请求中读取更新的认证文件。不要提交或公开密码文件；本机健康检查免认证。HTTP Basic 不加密，请使用可信网络或 TLS/SSH 隧道访问。Nginx 固定上游 Host 为 localhost，避免外部域名被 Vite 拒绝。

更新时先停止对应环境，再重新 `prepare` 和 `start`；会覆盖项目文件但保留运行日志。复制不包含 `.env`、Git 元数据、开发目录的依赖和构建产物，不要将凭据放进其他源码文件。可通过 `CLAWLIBRARY_ENV_ROOT` 更改根目录（绝对路径、不含空格），`NGINX_BIN` 指定 Nginx。默认两套环境读取同一份 OpenClaw 数据，若需数据隔离，分别配置部署目录中的 `clawlibrary.config.json`。不要从部署副本本身运行初始化。

## 开发命令

```bash
npm run dev
npm run validate
npm run typecheck
npm run build
```

可选 QA 命令：

```bash
npm run qa:movement
npm run qa:visual:baseline
npm run qa:visual
```

这些 QA 命令会在本地生成临时产物；当前默认输出到 `tmp/qa/`，不属于公开仓库内容。

## 运行模型

龙虾图书馆 / ClawLibrary 由协议数据和实时遥测共同驱动：

- `src/data/map.logic.json` — 房间布局、锚点、步行图、工作区域
- `src/data/asset.manifest.json` — 资产逻辑定义
- `src/data/scene-art.manifest.json` — 角色与场景美术绑定
- `src/data/work-output.protocol.json` — 工作状态与输出语义映射
- `scripts/openclaw-telemetry.mjs` — OpenClaw 状态到博物馆实时信号的桥接层

## 配置

龙虾图书馆 / ClawLibrary 现在使用根目录的 `clawlibrary.config.json` 作为公开版配置入口。

当前配置项包括：

- `debug` — 是否显示房间锚点、路径圆圈等调试可视化
- `host` — `127.0.0.1` 表示仅本机访问，`0.0.0.0` 或局域网 IP 表示允许共享访问
- `port` — 开发服务端口
- `auth.password` — 只要 `host` 不是本机地址，就必须配置访问密码
- `auth.sessionTtlHours` — 密码登录后的会话有效时长
- `locale` — `en` 或 `zh`
- `defaultActorVariant` — 默认角色外观

当前仓库默认附带的配置文件：

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

辅助文件：

- `.env.example` — 用于展示可选环境变量覆盖
- `scripts/clawlibrary-config.mjs` — 统一读取配置文件与环境变量

可选环境变量覆盖：

- `CLAWLIBRARY_SERVER_HOST`
- `CLAWLIBRARY_SERVER_PORT`
- `CLAWLIBRARY_ACCESS_PASSWORD`
- `CLAWLIBRARY_SESSION_TTL_HOURS`

安全说明：

- 仓库自带配置现在默认监听 `127.0.0.1`。
- 如果你把 ClawLibrary 绑定到 `0.0.0.0` 或其他非本机地址，ClawLibrary 会优先使用 `auth.password` / `CLAWLIBRARY_ACCESS_PASSWORD`，否则会在启动时提示你为当前进程输入一次访问密码。
- 如果是非交互式启动，请提前配置 `auth.password` 或 `CLAWLIBRARY_ACCESS_PASSWORD`，因为这时不会有终端密码提示。

## OpenClaw 路径探测

龙虾图书馆 / ClawLibrary 不会写死到某一台电脑的绝对路径。

它当前的策略是：

- 先读取 `clawlibrary.config.json`
- 如果设置了 `OPENCLAW_HOME`，则覆盖配置
- 如果设置了 `OPENCLAW_WORKSPACE`，则覆盖配置
- 如果配置和环境变量都未设置，则默认使用标准 OpenClaw 路径：
  - `~/.openclaw`
  - `~/.openclaw/workspace`

也就是说：

- 对标准 OpenClaw 安装，通常可直接工作
- 对自定义安装路径，可以通过配置或环境变量覆盖


## License

代码采用 MIT License：

- `/LICENSE`

素材采用 CC BY-NC-SA 4.0：

- `/LICENSE-ASSETS.md`
- 允许在署名条件下进行非商用分享、改编和再分发。
- 如果你分发改编后的素材，需要继续使用同样的许可。
- 如果你要将本项目用于商业用途，请替换掉仓库内附带的美术素材，或另行取得原素材授权。

## 鸣谢

- 本项目的界面与方向受到 [Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI) 的启发。
- 特别鸣谢 [@simonxxooxxoo](https://github.com/simonxxooxxoo) 与 [@ringhyacinth](https://github.com/ringhyacinth)。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=shengyu-meng/ClawLibrary&type=Date)](https://www.star-history.com/#shengyu-meng/ClawLibrary&Date)
