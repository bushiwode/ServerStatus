# ServerStatus


基于 [cppla/ServerStatus](https://github.com/cppla/ServerStatus) 的轻量级多服务器监控面板。这个 Fork 增加了交互式节点管理、systemd Agent、Telegram 通知，以及可切换的 Classic / Modern 两套中英文 Web 界面。

## 功能

- CPU、内存、磁盘、负载、网络、月流量与三网延迟监控
- Classic 密集表格和 Modern 仪表盘自由切换，选择自动保存在浏览器
- 简体中文和英文自动适配浏览器语言，也可以手动切换
- 明亮、深色、跟随系统三种主题
- 交互式节点增删改查，修改前自动备份配置
- Agent 以 systemd 服务运行并自动重连
- Telegram 上下线通知、连续状态防抖和发送失败退避
- 固定多架构镜像，支持 `linux/amd64`、`linux/arm64`、`linux/arm/v7`

## 使用指南

### 1. 安装服务端

准备一台使用 systemd 的 Linux 服务器和 root 权限。安装脚本会检查或安装 Docker、Docker Compose v2、curl 和 jq。

```bash
mkdir -p /root/data/docker_data/serverstatus
cd /root/data/docker_data/serverstatus

curl --fail --location \
  https://raw.githubusercontent.com/bushiwode/ServerStatus/master/sss.sh \
  -o sss.sh

chmod +x sss.sh
sudo ./sss.sh
```

安装完成后：

- Web 面板：`http://服务器IP:8081`
- Agent 上报端口：TCP `35601`
- 管理脚本会自动进入节点操作菜单

服务器防火墙需要放行 `8081/tcp` 和 `35601/tcp`。如果 Web 面板通过反向代理访问，可以只将 `8081` 绑定到本机，配置方式见下文。

### 2. 使用 Web 面板

页面右上角提供三组切换：

- `Classic / Modern`：切换经典密集表格与现代仪表盘。首次访问默认 Classic，选择会保存在当前浏览器。
- `中 / EN`：切换简体中文和英文。首次访问跟随浏览器语言，手动选择后会保存在当前浏览器。
- 太阳 / 月亮 / 屏幕：切换明亮、深色和跟随系统主题。

Modern 视图支持节点名称、地区搜索和在线状态筛选；Classic 视图在窄屏设备上可以横向滑动查看全部指标。

### 3. 添加和管理节点

在服务端项目目录重新运行管理脚本：

```bash
cd /root/data/docker_data/serverstatus
sudo ./sss.sh
```

菜单包含：

1. 查看节点
2. 添加节点
3. 删除节点
4. 更新节点名称、地区、类型和月流量起始日

选择“添加节点”后，脚本会生成 Agent 安装命令，并单独显示一次节点密码。复制命令到需要监控的机器执行，在隐藏输入提示中粘贴密码。

Agent 凭据保存在被监控服务器的 `/etc/sss-agent.env`，权限为 `0600`，不会出现在 systemd `ExecStart` 或进程参数中。

在被监控机器检查 Agent：

```bash
systemctl status sss-agent --no-pager
journalctl -u sss-agent -n 100 --no-pager
```

需要重新安装或卸载 Agent 时：

```bash
curl --fail --location \
  https://raw.githubusercontent.com/bushiwode/ServerStatus/master/agent/sss-agent.sh \
  -o sss-agent.sh

chmod +x sss-agent.sh
sudo ./sss-agent.sh
```

### 4. 启用 Telegram 通知

准备 Telegram Bot Token 和接收通知的 Chat ID，然后在服务端执行：

```bash
cd /root/data/docker_data/serverstatus
sudo ./sss.sh --telegram
```

脚本会交互读取 Chat ID 和 Bot Token，Token 不会出现在 Shell 历史中。配置保存在权限为 `0600` 的 `.env`，不会写入 `docker-compose.yml`。

检查 Telegram Bot 状态：

```bash
docker compose --profile telegram ps
docker compose --profile telegram logs --tail=100 bot
```

如果 Bot Token 曾出现在截图、聊天记录或公开仓库中，应立即通过 BotFather 撤销并重新生成。

### 5. 更新

更新会保留 `config.json`、`.env` 和 `json/` 中的历史数据。管理脚本会先安全更新自身，再验证并拉取新镜像；启动失败时尝试恢复原部署。

```bash
cd /root/data/docker_data/serverstatus
sudo ./sss.sh --upgrade
```

2026-08-24 之前安装的旧脚本不支持自动更新，仅首次过渡需要重新下载一次 `sss.sh`；此后都只需执行上面的升级命令。

更新后确认容器状态：

```bash
docker compose --profile telegram ps
docker compose --profile telegram images
```

### 6. 从旧版 ServerStatus 迁移

建议先完整备份原目录，然后在原目录运行最新版安装脚本：

```bash
cp -a /root/data/docker_data/serverstatus \
  /root/data/docker_data/serverstatus.backup

cd /root/data/docker_data/serverstatus
curl --fail --location \
  https://raw.githubusercontent.com/bushiwode/ServerStatus/master/sss.sh \
  -o sss.sh
chmod +x sss.sh
sudo ./sss.sh --upgrade
```

升级脚本会继续使用原有 `config.json` 和统计数据，但会将旧 Compose 服务替换为 `srv`、`web`，启用 Telegram 时还会包含 `bot`。

### 7. 常用运维命令

```bash
# 查看全部服务
docker compose --profile telegram ps

# 查看服务端和 Web 日志
docker compose logs --tail=100 srv web

# 查看 Telegram Bot 日志
docker compose --profile telegram logs --tail=100 bot

# 重启服务
docker compose --profile telegram restart

# 检查 Web 和统计数据
curl --fail http://127.0.0.1:8081/
curl --fail http://127.0.0.1:8081/json/stats.json
```

### 8. 自定义端口和监听地址

可以在项目目录的 `.env` 中设置：

```dotenv
SSS_WEB_BIND=127.0.0.1
SSS_WEB_PORT=8081
SSS_REPORT_BIND=0.0.0.0
SSS_REPORT_PORT=35601
```

修改后重新应用：

```bash
docker compose up -d --wait --wait-timeout 90
```

## 数据文件

| 路径 | 用途 |
| --- | --- |
| `config.json` | 节点账号、密码和展示信息，权限 `0600` |
| `config.json.bak` | 最近一次节点增删改前的配置备份 |
| `.env` | Telegram、端口和其他环境变量，权限 `0600` |
| `json/stats.json` | 服务端生成的当前统计数据 |

不要提交 `.env`、`config.json` 或 `json/` 目录；这些路径已经加入 `.gitignore`。

## 安全建议

- 公网部署时使用 HTTPS 反向代理，并为面板增加访问控制。
- 只通过本机反向代理访问面板时，设置 `SSS_WEB_BIND=127.0.0.1`。
- TCP `35601` 当前沿用上游明文协议，建议通过 WireGuard、Tailscale 或受控防火墙连接 Agent。
- 定期备份 `config.json`、`.env` 和 `json/`。

## 开发检查

```bash
bash -n sss.sh agent/sss-agent.sh
bash tests/test_installer.sh
python3 -m unittest discover -s tests -v
node --check service/web/js/app.js
node --test tests/test_web.js
docker compose config --quiet
docker compose --profile telegram config --quiet
```

项目使用 MIT License。
