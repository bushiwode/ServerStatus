#!/bin/bash

set -u

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ /
#     Arch 未测试
#   Description: Server Status 监控安装 + 节点管理脚本
#   Github: https://github.com/bushiwode/ServerStatus
#========================================================

GITHUB_RAW_URL="${SSS_RAW_BASE:-https://raw.githubusercontent.com/bushiwode/ServerStatus/master}"
CONFIG_FILE="config.json"
COMPOSE_CMD=()
FORCE_INSTALL=0
CONFIGURE_BOT_STAGE=""
INSTALL_STAGE=""
INSTALL_HAD_PREVIOUS_COMPOSE=0
INSTALL_HAD_PREVIOUS_ENV=0
INSTALL_ENV_MAY_BE_REPLACED=0
INSTALL_COMPOSE_MAY_BE_REPLACED=0
INSTALL_STACK_TOUCHED=0
INSTALL_COMMITTED=0

# ---- 颜色(真实 ESC 字符, printf/echo 通用) ----
red=$'\e[0;31m'
green=$'\e[0;32m'
yellow=$'\e[0;33m'
blue=$'\e[0;34m'
cyan=$'\e[0;36m'
bold=$'\e[1m'
dim=$'\e[2m'
plain=$'\e[0m'
export PATH="${PATH}:/usr/local/bin"

# ---- UI 助手 ----
banner() {
    printf '%s\n' "${cyan}${bold}"
    cat <<'EOF'
   ____                          ____  _        _
  / ___|  ___ _ ____   _____ _ _/ ___|| |_ __ _| |_ _   _ ___
  \___ \ / _ \ '__\ \ / / _ \ '__\___ \| __/ _` | __| | | / __|
   ___) |  __/ |   \ V /  __/ |   ___) | || (_| | |_| |_| \__ \
  |____/ \___|_|    \_/ \___|_|  |____/ \__\__,_|\__|\__,_|___/
EOF
    printf '%s\n' "${plain}${dim}  最简洁的探针 · ServerStatus 面板管理${plain}"
}
line() { printf '%s\n' "${dim}  ────────────────────────────────────────────${plain}"; }
info() { printf '%s\n' "${cyan}[*]${plain} $*"; }
ok()   { printf '%s\n' "${green}[✓]${plain} $*"; }
warn() { printf '%s\n' "${yellow}[!]${plain} $*"; }
err()  { printf '%s\n' "${red}[✗]${plain} $*"; }
step() { printf '\n%s\n' "${blue}${bold}»${plain} ${bold}$*${plain}"; }
ask()  { printf '%s' "${cyan}»${plain} $* "; }
pause(){ printf '\n%s' "${dim}按回车继续…${plain}"; read -r _; }
die()  { err "$*"; exit 1; }

download_file() {
    local url="$1" destination="$2"
    if ! curl --fail --show-error --silent --location \
        --retry 3 --connect-timeout 10 --output "$destination" "$url"; then
        err "文件下载失败：${url}"
        return 1
    fi
    if [ ! -s "$destination" ]; then
        err "下载文件为空：${url}"
        return 1
    fi
}

compose() {
    "${COMPOSE_CMD[@]}" "$@"
}

compose_file() {
    local file="$1" env_file="$2"
    shift 2
    if [ -f "$env_file" ]; then
        "${COMPOSE_CMD[@]}" --project-directory "$PWD" --env-file "$env_file" -f "$file" "$@"
    else
        "${COMPOSE_CMD[@]}" --project-directory "$PWD" -f "$file" "$@"
    fi
}

atomic_replace() {
    local source="$1" destination="$2" mode="$3" destination_dir destination_name temporary
    destination_dir=$(dirname -- "$destination")
    destination_name=$(basename -- "$destination")
    temporary=$(mktemp "${destination_dir}/.${destination_name}.tmp.XXXXXX") || return 1
    if ! install -m "$mode" "$source" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    if ! mv -f -- "$temporary" "$destination"; then
        rm -f -- "$temporary"
        return 1
    fi
}

update_script_file() {
    local current_path="$1" stage
    stage=$(mktemp -d) || die "创建脚本更新暂存目录失败"
    chmod 0700 "$stage" || { rm -rf -- "$stage"; die "保护脚本更新暂存目录失败"; }
    if ! download_file "${GITHUB_RAW_URL}/sss.sh" "${stage}/sss.sh"; then
        rm -rf -- "$stage"
        die "管理脚本更新下载失败，现有部署未修改"
    fi
    if ! bash -n "${stage}/sss.sh"; then
        rm -rf -- "$stage"
        die "新管理脚本校验失败，现有脚本未修改"
    fi
    if cmp -s "${stage}/sss.sh" "$current_path"; then
        rm -rf -- "$stage"
        return 1
    fi
    if ! atomic_replace "${stage}/sss.sh" "$current_path" 0755; then
        rm -rf -- "$stage"
        die "管理脚本原子更新失败，现有部署未修改"
    fi
    rm -rf -- "$stage"
}

self_update_and_exec() {
    [[ "${SSS_SKIP_SELF_UPDATE:-0}" == "1" ]] && return
    local source_path script_dir script_path
    source_path="${BASH_SOURCE[0]}"
    if [ ! -f "$source_path" ]; then
        warn "当前运行方式无法自动更新脚本，将继续升级面板"
        return
    fi
    script_dir=$(cd -- "$(dirname -- "$source_path")" && pwd) || die "无法定位管理脚本目录"
    script_path="${script_dir}/$(basename -- "$source_path")"
    if update_script_file "$script_path"; then
        ok "管理脚本已更新，继续升级面板"
        export SSS_SKIP_SELF_UPDATE=1
        exec "$script_path" --upgrade "$@"
        die "无法重新运行更新后的管理脚本"
    fi
}

pre_check() {
    command -v systemctl >/dev/null 2>&1 || die "不支持此系统：未找到 systemctl 命令"
    [[ ${EUID} -eq 0 ]] || die "必须使用 root 用户运行此脚本"
}

install_soft() {
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$@"
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y "$@"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm "$@"
    else
        return 1
    fi
}

install_base() {
    local packages=()
    command -v curl >/dev/null 2>&1 || packages+=(curl)
    command -v jq >/dev/null 2>&1 || packages+=(jq)
    if [[ ${#packages[@]} -gt 0 ]]; then
        install_soft "${packages[@]}" || die "安装基础软件失败"
    fi
}

detect_compose() {
    local up_help ps_help
    docker compose version >/dev/null 2>&1 || return 1
    up_help=$(docker compose up --help 2>/dev/null) || return 1
    ps_help=$(docker compose ps --help 2>/dev/null) || return 1
    [[ "$up_help" =~ (^|[[:space:]])--wait([=[:space:]]|$) ]] || return 1
    [[ "$up_help" =~ (^|[[:space:]])--wait-timeout([=[:space:]]|$) ]] || return 1
    [[ "$ps_help" =~ (^|[[:space:]])--status([=[:space:]]|$) ]] || return 1
    COMPOSE_CMD=(docker compose)
}

install_docker() {
    install_base
    if ! command -v docker >/dev/null 2>&1; then
        local installer
        info "正在安装 Docker"
        installer=$(mktemp)
        download_file "https://get.docker.com" "$installer" || { rm -f "$installer"; die "Docker 安装脚本下载失败"; }
        sh "$installer" || { rm -f "$installer"; die "Docker 安装失败"; }
        rm -f "$installer"
        systemctl enable docker.service
        systemctl start docker.service
        ok "Docker 安装成功"
    fi

    if ! detect_compose; then
        info "正在安装或升级 Docker Compose v2 插件（需支持 up --wait/--wait-timeout 与 ps --status）"
        install_soft docker-compose-plugin || die "Docker Compose v2 安装失败，请安装支持 up --wait/--wait-timeout 与 ps --status 的 docker compose 插件"
        detect_compose || die "Docker Compose v2 能力不足：需要 docker compose up --wait/--wait-timeout 和 docker compose ps --status"
    fi
}

cleanup_configure_bot_stage() {
    local stage="$CONFIGURE_BOT_STAGE"
    if [[ -z "$stage" ]]; then
        return 0
    fi
    if rm -rf -- "$stage"; then
        CONFIGURE_BOT_STAGE=""
        return 0
    fi
    chmod 0700 "$stage" 2>/dev/null || true
    return 1
}

reset_install_transaction() {
    trap - HUP INT TERM
    INSTALL_STAGE=""
    INSTALL_HAD_PREVIOUS_COMPOSE=0
    INSTALL_HAD_PREVIOUS_ENV=0
    INSTALL_ENV_MAY_BE_REPLACED=0
    INSTALL_COMPOSE_MAY_BE_REPLACED=0
    INSTALL_STACK_TOUCHED=0
    INSTALL_COMMITTED=0
}

abort_install() {
    local stage="$1" message="$2" configure_stage="$CONFIGURE_BOT_STAGE" retained=""
    if ! cleanup_configure_bot_stage; then
        err "Telegram 临时目录清理失败，路径保留在 ${configure_stage}"
        retained="$configure_stage"
    fi
    if ! rm -rf -- "$stage"; then
        chmod 0700 "$stage" 2>/dev/null || true
        retained="$stage"
    fi
    if [[ -n "$retained" ]]; then
        die "${message}；暂存清理失败，路径保留在 ${retained}"
    fi
    die "$message"
}

retain_install_stage() {
    local stage="$1" message="$2" configure_stage="$CONFIGURE_BOT_STAGE"
    if ! cleanup_configure_bot_stage; then
        err "Telegram 临时目录清理失败，路径保留在 ${configure_stage}"
    fi
    chmod 0700 "$stage" 2>/dev/null || true
    die "${message}；暂存与备份保留在 ${stage}"
}

restore_env() {
    local stage="$1" had_previous_env="$2"
    if [[ ${had_previous_env} -eq 1 ]]; then
        atomic_replace "${stage}/env.previous" .env 0600
    else
        rm -f .env
    fi
}

rollback_install_transaction() {
    local stage="$1" failed=0 compose_restored=1 env_restored=1

    if [[ ${INSTALL_STACK_TOUCHED} -eq 1 ]]; then
        compose down || {
            warn "未能完整停止新栈，继续尝试恢复原部署"
            failed=1
        }
    fi

    if [[ ${INSTALL_ENV_MAY_BE_REPLACED} -eq 1 ]] && ! restore_env "$stage" "$INSTALL_HAD_PREVIOUS_ENV"; then
        env_restored=0
        failed=1
    fi

    if [[ ${INSTALL_COMPOSE_MAY_BE_REPLACED} -eq 1 ]]; then
        if [[ ${INSTALL_HAD_PREVIOUS_COMPOSE} -eq 1 ]]; then
            if ! atomic_replace "${stage}/docker-compose.yml.previous" docker-compose.yml 0644; then
                compose_restored=0
                failed=1
            fi
        elif ! rm -f docker-compose.yml; then
            compose_restored=0
            failed=1
        fi
    fi

    if [[ ${INSTALL_STACK_TOUCHED} -eq 1 && ${INSTALL_HAD_PREVIOUS_COMPOSE} -eq 1 && ${compose_restored} -eq 1 && ${env_restored} -eq 1 ]]; then
        compose up -d || failed=1
    fi

    if [[ ${failed} -eq 0 ]]; then
        INSTALL_ENV_MAY_BE_REPLACED=0
        INSTALL_COMPOSE_MAY_BE_REPLACED=0
        INSTALL_STACK_TOUCHED=0
    fi
    return "$failed"
}

install_signal_handler() {
    local signal="$1" exit_code=1 stage="$INSTALL_STAGE" configure_stage="$CONFIGURE_BOT_STAGE" failed=0
    case "$signal" in
        HUP) exit_code=129 ;;
        INT) exit_code=130 ;;
        TERM) exit_code=143 ;;
    esac
    trap - HUP INT TERM

    if ! cleanup_configure_bot_stage; then
        failed=1
        err "Telegram 临时目录清理失败，路径保留在 ${configure_stage}"
    fi

    if [[ -n "$stage" ]]; then
        if [[ ${INSTALL_COMMITTED} -eq 0 ]]; then
            rollback_install_transaction "$stage" || failed=1
        fi
        if [[ ${failed} -eq 0 ]]; then
            if rm -rf -- "$stage"; then
                if [[ ${INSTALL_COMMITTED} -eq 1 ]]; then
                    err "安装完成后收到 ${signal} 信号，新部署保持运行，暂存已清理"
                else
                    err "安装被 ${signal} 信号中断，原部署已恢复"
                fi
            else
                failed=1
            fi
        fi
        if [[ ${failed} -ne 0 ]]; then
            chmod 0700 "$stage" 2>/dev/null || true
            err "安装被 ${signal} 信号中断，恢复或清理未完全成功；暂存与备份保留在 ${stage}"
        fi
    fi
    exit "$exit_code"
}

begin_install_transaction() {
    INSTALL_STAGE="$1"
    INSTALL_HAD_PREVIOUS_COMPOSE="$2"
    INSTALL_HAD_PREVIOUS_ENV="$3"
    INSTALL_ENV_MAY_BE_REPLACED=0
    INSTALL_COMPOSE_MAY_BE_REPLACED=0
    INSTALL_STACK_TOUCHED=0
    INSTALL_COMMITTED=0
    trap 'install_signal_handler HUP' HUP
    trap 'install_signal_handler INT' INT
    trap 'install_signal_handler TERM' TERM
}

configure_bot() {
    local destination="$1" chat_id="" token="" grep_status
    shift
    if [[ $# -eq 0 ]]; then
        if [ -f .env ]; then
            install -m 0600 .env "$destination"
        else
            rm -f -- "$destination"
        fi
        return
    elif [[ $# -eq 1 && "$1" == "--telegram" ]]; then
        if ! read -r -p "Telegram Chat ID: " chat_id; then
            err "读取 Telegram Chat ID 失败"
            return 1
        fi
        if ! read -r -s -p "Telegram Bot Token: " token; then
            echo
            err "读取 Telegram Bot Token 失败"
            return 1
        fi
        echo
    elif [[ $# -eq 2 ]]; then
        warn "命令行参数会进入 Shell 历史，后续建议使用 --telegram 交互配置"
        chat_id="$1"
        token="$2"
    else
        err "Telegram 配置参数无效"
        return 1
    fi

    if [[ ! "$chat_id" =~ ^-?[0-9]+$ && ! "$chat_id" =~ ^@[A-Za-z0-9_]+$ ]]; then
        err "Telegram Chat ID 格式无效"
        return 1
    fi
    if [[ ! "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        err "Telegram Bot Token 格式无效"
        return 1
    fi

    CONFIGURE_BOT_STAGE=$(mktemp -d) || {
        err "创建 Telegram 配置暂存目录失败"
        return 1
    }
    chmod 0700 "$CONFIGURE_BOT_STAGE" || {
        cleanup_configure_bot_stage || true
        err "保护 Telegram 配置暂存目录失败"
        return 1
    }
    if [ -f .env ]; then
        grep -vE '^(TG_CHAT_ID|TG_BOT_TOKEN|COMPOSE_PROFILES)=' .env > "${CONFIGURE_BOT_STAGE}/env"
        grep_status=$?
        if [[ ${grep_status} -gt 1 ]]; then
            cleanup_configure_bot_stage || true
            err "读取现有 .env 失败"
            return 1
        fi
    else
        : > "${CONFIGURE_BOT_STAGE}/env"
    fi
    if ! printf 'TG_CHAT_ID=%s\nTG_BOT_TOKEN=%s\nCOMPOSE_PROFILES=telegram\n' "$chat_id" "$token" >> "${CONFIGURE_BOT_STAGE}/env"; then
        cleanup_configure_bot_stage || true
        err "生成 Telegram 配置失败"
        return 1
    fi
    if ! atomic_replace "${CONFIGURE_BOT_STAGE}/env" "$destination" 0600; then
        cleanup_configure_bot_stage || true
        err "Telegram 配置保存失败"
        return 1
    fi
    if ! cleanup_configure_bot_stage; then
        err "Telegram 临时目录清理失败，路径保留在 ${CONFIGURE_BOT_STAGE}"
        return 1
    fi
}

install_dashboard() {
    local stage had_previous_compose=0 had_previous_env=0
    install_docker

    if [[ ${FORCE_INSTALL} -eq 0 && $# -eq 0 ]] && compose ps --status running --services 2>/dev/null | grep -qx web; then
        return 0
    fi

    step "安装面板"
    stage=$(mktemp -d) || die "创建安装暂存目录失败"
    chmod 0700 "$stage" || { rm -rf -- "$stage"; die "保护安装暂存目录失败"; }
    [ -f .env ] && had_previous_env=1
    [ -f docker-compose.yml ] && had_previous_compose=1
    begin_install_transaction "$stage" "$had_previous_compose" "$had_previous_env"
    if [ -f .env ]; then
        install -m 0600 .env "${stage}/env.previous" || {
            abort_install "$stage" "备份现有 .env 失败，部署未修改"
        }
    fi
    if [ -f docker-compose.yml ]; then
        install -m 0644 docker-compose.yml "${stage}/docker-compose.yml.previous" || {
            abort_install "$stage" "备份现有 Compose 失败，部署未修改"
        }
    fi

    download_file "${GITHUB_RAW_URL}/docker-compose.yml" "${stage}/docker-compose.yml" || {
        abort_install "$stage" "Compose 下载失败，部署未修改"
    }
    if ! configure_bot "${stage}/env.next" "$@"; then
        abort_install "$stage" "Telegram 配置失败，原 .env 未修改"
    fi

    if ! compose_file "${stage}/docker-compose.yml" "${stage}/env.next" config --quiet; then
        abort_install "$stage" "新 Compose 配置无效，现有部署未修改"
    fi
    if ! compose_file "${stage}/docker-compose.yml" "${stage}/env.next" pull; then
        abort_install "$stage" "新镜像拉取失败，现有部署未修改"
    fi

    install -d -m 0755 json || {
        abort_install "$stage" "创建数据目录失败，Compose 尚未替换"
    }
    if [ ! -f json/stats.json ]; then
        printf '%s\n' '{"servers":[],"sslcerts":[]}' > "${stage}/stats.json"
        install -m 0644 "${stage}/stats.json" json/stats.json || {
            abort_install "$stage" "初始化 stats.json 失败，Compose 尚未替换"
        }
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        printf '%s\n' '{"servers":[]}' > "$CONFIG_FILE"
    fi
    chmod 0600 "$CONFIG_FILE"

    if [ -f "${stage}/env.next" ]; then
        INSTALL_ENV_MAY_BE_REPLACED=1
        if ! atomic_replace "${stage}/env.next" .env 0600; then
            if rollback_install_transaction "$stage"; then
                abort_install "$stage" "原子应用 .env 失败，原部署已恢复"
            fi
            retain_install_stage "$stage" "原子应用 .env 失败且自动恢复未完全成功"
        fi
    fi

    INSTALL_COMPOSE_MAY_BE_REPLACED=1
    if ! atomic_replace "${stage}/docker-compose.yml" docker-compose.yml 0644; then
        if rollback_install_transaction "$stage"; then
            abort_install "$stage" "原子替换 Compose 失败，原部署已恢复"
        fi
        retain_install_stage "$stage" "原子替换 Compose 失败且自动恢复未完全成功"
    fi

    step "启动面板"
    INSTALL_STACK_TOUCHED=1
    if ! compose up -d --wait --wait-timeout 90; then
        if [[ ${had_previous_compose} -eq 1 ]]; then
            warn "新栈启动失败，正在恢复旧 Compose"
            if rollback_install_transaction "$stage"; then
                abort_install "$stage" "新栈启动失败，已恢复旧 Compose 并重新启动旧栈"
            fi
            retain_install_stage "$stage" "新栈启动失败，旧栈自动恢复未完全成功"
        fi

        if rollback_install_transaction "$stage"; then
            abort_install "$stage" "首次安装启动失败，新栈和新 Compose 已清理；配置和数据已保留"
        fi
        retain_install_stage "$stage" "首次安装启动失败，自动清理未完全成功"
    fi

    INSTALL_COMMITTED=1
    if ! rm -rf -- "$stage"; then
        retain_install_stage "$stage" "面板已启动，但含敏感配置的暂存目录清理失败"
    fi
    reset_install_transaction
    ok "面板已启动，web 地址：http://<本机IP>:8081"
}

# ================= 节点管理(纯 shell + jq) =================

ensure_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        printf '%s\n' '{"servers":[]}' > "$CONFIG_FILE"
        chmod 0600 "$CONFIG_FILE"
    fi
    jq -e '.servers | type == "array"' "$CONFIG_FILE" >/dev/null 2>&1 || die "config.json 格式无效"
}

get_ip() {
    local ip
    ip=$(curl --fail --silent --max-time 10 https://api.ipify.org 2>/dev/null || true)
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ || "$ip" =~ ^[0-9A-Fa-f:]+$ ]]; then
        printf '%s' "$ip"
    else
        printf '%s' "<本机IP>"
    fi
}

gen_user() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        tr -d '-' < /proc/sys/kernel/random/uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr -d '-' | tr 'A-Z' 'a-z'
    else
        head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

gen_pass() {
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

restart_stack() {
    info "操作完成，等待服务重启…"
    compose restart || { err "服务重启失败"; return 1; }
    ok "完成"
}

print_agent_cmd() {
    local user="$1" pass="$2" ip
    ip=$(get_ip)
    echo
    line
    printf '%s\n' "${green}curl --fail --location ${GITHUB_RAW_URL}/agent/sss-agent.sh -o sss-agent.sh && chmod +x sss-agent.sh && sudo ./sss-agent.sh install ${ip} ${user}${plain}"
    printf '%s\n' "${yellow}节点密码（安装时粘贴）: ${pass}${plain}"
    line
}

show_node_install() {
    ensure_config
    list_nodes
    local count idx name user pass
    count=$(jq '.servers | length' "$CONFIG_FILE")
    [ "$count" -eq 0 ] && return
    echo
    ask "请输入要查看安装信息的节点编号:"; read -r idx
    [[ "$idx" =~ ^[0-9]+$ ]] || { err "无效输入"; return; }
    [ "$idx" -ge "$count" ] && { err "编号超出范围"; return; }

    if ! jq -e ".servers[$idx] | (.username | type == \"string\" and length > 0) and (.password | type == \"string\" and length > 0)" "$CONFIG_FILE" >/dev/null; then
        err "该节点的安装凭据不完整，请重新添加节点"
        return
    fi
    name=$(jq -r ".servers[$idx].name" "$CONFIG_FILE")
    user=$(jq -r ".servers[$idx].username" "$CONFIG_FILE")
    pass=$(jq -r ".servers[$idx].password" "$CONFIG_FILE")

    warn "以下信息包含节点凭据，请勿公开转发"
    info "请复制以下命令在机器 ${bold}${name}${plain} 重新安装 agent 服务:"
    print_agent_cmd "$user" "$pass"
}

list_nodes() {
    ensure_config
    local count
    count=$(jq '.servers | length' "$CONFIG_FILE")
    echo
    if [ "$count" -eq 0 ]; then
        warn "暂时没有任何节点，使用「添加节点」开始吧"
        return
    fi
    printf "  ${bold}%-5s %-18s %-10s %-8s${plain}\n" "ID" "NAME" "LOCATION" "TYPE"
    line
    jq -r '.servers | to_entries[] | "\(.key)|\(.value.name)|\(.value.location)|\(.value.type)"' "$CONFIG_FILE" |
    while IFS='|' read -r id name loc type; do
        printf "  %-5s %-18s %-10s %-8s\n" "$id" "$name" "$loc" "$type"
    done
}

add_node() {
    ensure_config
    local name loc type user pass tmp
    echo
    ask "请输入节点名字:"; read -r name
    [ -z "$name" ] && { err "名字不能为空"; return; }
    if jq -e --arg name "$name" '.servers | any(.name == $name)' "$CONFIG_FILE" >/dev/null; then
        err "节点名字已存在"
        return
    fi
    ask "请输入位置 [us]:"; read -r loc;  loc=${loc:-us}
    ask "请输入类型 [kvm]:"; read -r type; type=${type:-kvm}

    user=$(gen_user)
    pass=$(gen_pass)

    cp -p "$CONFIG_FILE" "${CONFIG_FILE}.bak" || { err "配置备份失败"; return; }
    tmp=$(mktemp)
    jq --arg name "$name" --arg loc "$loc" --arg type "$type" --arg user "$user" --arg pass "$pass" \
       '.servers += [{monthstart:"1",location:$loc,type:$type,name:$name,username:$user,host:$name,password:$pass}] | .servers |= sort_by(.name)' \
       "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE" || { err "写入 config.json 失败"; rm -f "$tmp"; return; }

    ok "添加成功: ${bold}${name}${plain}"
    restart_stack
    list_nodes
    echo
    info "请复制以下命令在机器 ${bold}${name}${plain} 安装 agent 服务:"
    print_agent_cmd "$user" "$pass"
}

remove_node() {
    ensure_config
    list_nodes
    local count idx name yn tmp
    count=$(jq '.servers | length' "$CONFIG_FILE")
    [ "$count" -eq 0 ] && return
    echo
    ask "请输入要删除的节点编号:"; read -r idx
    [[ "$idx" =~ ^[0-9]+$ ]] || { err "无效输入"; return; }
    [ "$idx" -ge "$count" ] && { err "编号超出范围"; return; }
    name=$(jq -r ".servers[$idx].name" "$CONFIG_FILE")
    ask "确认删除节点 ${bold}${name}${plain}? [y/N]"; read -r yn
    case "$yn" in
        y|Y) ;;
        *) info "已取消删除"; return ;;
    esac
    cp -p "$CONFIG_FILE" "${CONFIG_FILE}.bak" || { err "配置备份失败"; return; }
    tmp=$(mktemp)
    jq "del(.servers[$idx])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE" || { err "写入失败"; rm -f "$tmp"; return; }
    ok "删除成功: ${bold}${name}${plain}"
    restart_stack
    list_nodes
}

update_node() {
    ensure_config
    list_nodes
    local count idx oname oloc otype omonth name loc type month tmp
    count=$(jq '.servers | length' "$CONFIG_FILE")
    [ "$count" -eq 0 ] && return
    echo
    ask "请输入要更新的节点编号:"; read -r idx
    [[ "$idx" =~ ^[0-9]+$ ]] || { err "无效输入"; return; }
    [ "$idx" -ge "$count" ] && { err "编号超出范围"; return; }

    oname=$(jq -r ".servers[$idx].name" "$CONFIG_FILE")
    oloc=$(jq -r ".servers[$idx].location" "$CONFIG_FILE")
    otype=$(jq -r ".servers[$idx].type" "$CONFIG_FILE")
    omonth=$(jq -r ".servers[$idx].monthstart" "$CONFIG_FILE")

    printf '%s\n' "${dim}回车保留原值(中括号内为原值)${plain}"
    ask "新名字 [${oname}]:";        read -r name;  name=${name:-$oname}
    ask "新位置 [${oloc}]:";         read -r loc;   loc=${loc:-$oloc}
    ask "新类型 [${otype}]:";        read -r type;  type=${type:-$otype}
    ask "月流量起始日 [${omonth}]:"; read -r month; month=${month:-$omonth}
    [[ "$month" =~ ^([1-9]|[12][0-9]|3[01])$ ]] || { err "月流量起始日必须为 1-31"; return; }
    if [ "$name" != "$oname" ] && jq -e --arg name "$name" '.servers | any(.name == $name)' "$CONFIG_FILE" >/dev/null; then
        err "节点名字已存在"
        return
    fi

    if [ "$name" = "$oname" ] && [ "$loc" = "$oloc" ] && [ "$type" = "$otype" ] && [ "$month" = "$omonth" ]; then
        info "未做任何更新，直接返回"
        return
    fi

    cp -p "$CONFIG_FILE" "${CONFIG_FILE}.bak" || { err "配置备份失败"; return; }
    tmp=$(mktemp)
    jq --arg n "$name" --arg l "$loc" --arg t "$type" --arg m "$month" \
       ".servers[$idx].name=\$n | .servers[$idx].location=\$l | .servers[$idx].type=\$t | .servers[$idx].monthstart=\$m | .servers |= sort_by(.name)" \
       "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE" || { err "写入失败"; rm -f "$tmp"; return; }

    ok "更新成功"
    restart_stack
    list_nodes
}

menu_loop() {
    ensure_config
    while true; do
        clear 2>/dev/null
        banner
        printf '%s\n' "${dim}  使用教程: https://github.com/Lau0x/ServerStatus#使用指南${plain}"
        list_nodes
        echo
        printf '%s\n' "  ${bold}操作菜单${plain}"
        printf '%s\n' "    ${green}1${plain}. 查看节点      ${green}2${plain}. 添加节点"
        printf '%s\n' "    ${green}3${plain}. 删除节点      ${green}4${plain}. 更新节点"
        printf '%s\n' "    ${green}5${plain}. 查看安装信息"
        printf '%s\n' "    ${green}0${plain}. 退出"
        echo
        ask "请输入操作编号:"; read -r op
        case "$op" in
            1) list_nodes; pause ;;
            2) add_node;    pause ;;
            3) remove_node; pause ;;
            4) update_node; pause ;;
            5) show_node_install; pause ;;
            0) echo; ok "再见 👋"; exit 0 ;;
            *) err "无效输入"; pause ;;
        esac
    done
}

# ================= 入口 =================
clear 2>/dev/null
banner
pre_check
if [[ "${1:-}" == "--upgrade" ]]; then
    shift
    self_update_and_exec "$@"
    FORCE_INSTALL=1
fi
install_dashboard "$@"
menu_loop
