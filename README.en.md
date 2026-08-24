# ServerStatus

[简体中文](README.md) | [English](README.en.md)

A lightweight multi-server monitoring dashboard based on [cppla/ServerStatus](https://github.com/cppla/ServerStatus). This fork adds interactive node management, a systemd agent, Telegram notifications, and bilingual Classic and Modern web interfaces.

## Features

- CPU, memory, disk, load, network, monthly traffic, and China carrier latency monitoring
- Switchable Classic table and Modern dashboard with browser-persisted preferences
- Simplified Chinese and English, selected automatically from the browser or manually
- Light, dark, and system color themes
- Interactive node management with automatic configuration backups
- A systemd agent with automatic reconnection
- Debounced Telegram online/offline notifications with retry backoff
- Pinned multi-architecture images for `linux/amd64`, `linux/arm64`, and `linux/arm/v7`

## Usage

### 1. Install the server

Prepare a Linux server with systemd and root access. The installer checks or installs Docker, Docker Compose v2, curl, and jq.

```bash
mkdir -p /root/data/docker_data/serverstatus
cd /root/data/docker_data/serverstatus

curl --fail --location \
  https://raw.githubusercontent.com/Lau0x/ServerStatus/master/sss.sh \
  -o sss.sh

chmod +x sss.sh
sudo ./sss.sh
```

After installation:

- Web dashboard: `http://SERVER_IP:8081`
- Agent reporting port: TCP `35601`
- The installer opens the node management menu automatically

Allow `8081/tcp` and `35601/tcp` through the server firewall. If the dashboard is behind a reverse proxy, you can bind port `8081` to localhost as described below.

### 2. Use the web dashboard

The top-right controls provide three choices:

- `Classic / Modern`: switch between the dense table and dashboard. Classic is the first-visit default, and the choice is stored in the current browser.
- `中 / EN`: switch between Simplified Chinese and English. The first visit follows the browser language; a manual choice is stored in the current browser.
- Sun / moon / screen: select light, dark, or system theme.

Modern view supports search by node or region and online-status filtering. Classic view can be scrolled horizontally on narrow screens.

### 3. Add and manage nodes

Run the manager again from the server directory:

```bash
cd /root/data/docker_data/serverstatus
sudo ./sss.sh
```

The menu can list, add, delete, and edit nodes. Editing covers the node name, region, type, and monthly traffic reset day.

When you add a node, the manager prints an agent installation command and displays the node password once. Run the command on the machine to be monitored and paste the password into the hidden prompt.

Agent credentials are stored in `/etc/sss-agent.env` with mode `0600`; they do not appear in systemd `ExecStart` or process arguments.

Check the agent on a monitored machine:

```bash
systemctl status sss-agent --no-pager
journalctl -u sss-agent -n 100 --no-pager
```

Reinstall or remove the agent with:

```bash
curl --fail --location \
  https://raw.githubusercontent.com/Lau0x/ServerStatus/master/agent/sss-agent.sh \
  -o sss-agent.sh

chmod +x sss-agent.sh
sudo ./sss-agent.sh
```

### 4. Enable Telegram notifications

Create a Telegram bot token and obtain the destination Chat ID, then run:

```bash
cd /root/data/docker_data/serverstatus
sudo ./sss.sh --telegram
```

The script reads the Chat ID and token interactively. The token is not written to shell history. Settings are stored in `.env` with mode `0600`, not in `docker-compose.yml`.

Check the bot:

```bash
docker compose --profile telegram ps
docker compose --profile telegram logs --tail=100 bot
```

If a bot token has appeared in a screenshot, chat, or public repository, revoke it through BotFather and create a new one immediately.

### 5. Update

Updates preserve `config.json`, `.env`, and historical data under `json/`. The management script safely updates itself first, then validates and pulls new images. If startup fails, it attempts to restore the previous deployment.

```bash
cd /root/data/docker_data/serverstatus
sudo ./sss.sh --upgrade
```

Scripts installed before 2026-08-24 do not support self-update and need one final manual `sss.sh` download. Later updates only require the command above.

Verify the deployment:

```bash
docker compose --profile telegram ps
docker compose --profile telegram images
```

### 6. Migrate from an older ServerStatus installation

Back up the existing directory, then run the current installer in that directory:

```bash
cp -a /root/data/docker_data/serverstatus \
  /root/data/docker_data/serverstatus.backup

cd /root/data/docker_data/serverstatus
curl --fail --location \
  https://raw.githubusercontent.com/Lau0x/ServerStatus/master/sss.sh \
  -o sss.sh
chmod +x sss.sh
sudo ./sss.sh --upgrade
```

The upgrade reuses the existing `config.json` and statistics, while replacing the old Compose services with `srv` and `web`; the optional Telegram profile also includes `bot`.

### 7. Common operations

```bash
# Show all services
docker compose --profile telegram ps

# Server and web logs
docker compose logs --tail=100 srv web

# Telegram bot logs
docker compose --profile telegram logs --tail=100 bot

# Restart services
docker compose --profile telegram restart

# Check the dashboard and statistics feed
curl --fail http://127.0.0.1:8081/
curl --fail http://127.0.0.1:8081/json/stats.json
```

### 8. Customize ports and bind addresses

Set values in the project `.env` file:

```dotenv
SSS_WEB_BIND=127.0.0.1
SSS_WEB_PORT=8081
SSS_REPORT_BIND=0.0.0.0
SSS_REPORT_PORT=35601
```

Apply the changes:

```bash
docker compose up -d --wait --wait-timeout 90
```

## Data files

| Path | Purpose |
| --- | --- |
| `config.json` | Node accounts, passwords, and display metadata; mode `0600` |
| `config.json.bak` | Backup created before the most recent node change |
| `.env` | Telegram, port, and other environment settings; mode `0600` |
| `json/stats.json` | Current statistics generated by the server |

Do not commit `.env`, `config.json`, or `json/`; these paths are already listed in `.gitignore`.

## Security recommendations

- Put the public dashboard behind an HTTPS reverse proxy with access control.
- Set `SSS_WEB_BIND=127.0.0.1` when only a local reverse proxy should reach the dashboard.
- TCP `35601` uses the upstream plaintext protocol. Prefer WireGuard, Tailscale, or a restricted firewall between agents and the server.
- Back up `config.json`, `.env`, and `json/` regularly.

## Development checks

```bash
bash -n sss.sh agent/sss-agent.sh
bash tests/test_installer.sh
python3 -m unittest discover -s tests -v
node --check service/web/js/app.js
node --test tests/test_web.js
docker compose config --quiet
docker compose --profile telegram config --quiet
```

MIT License.
