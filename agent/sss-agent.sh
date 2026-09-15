#!/bin/bash

set -Eeuo pipefail

SSS_BASE_PATH="/opt/sss"
SSS_AGENT_PATH="${SSS_BASE_PATH}/agent"
SSS_AGENT_SERVICE="/etc/systemd/system/sss-agent.service"
SSS_AGENT_ENV="/etc/sss-agent.env"
GITHUB_RAW_URL="${SSS_RAW_BASE:-https://raw.githubusercontent.com/bushiwode/ServerStatus/master}"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH="${PATH}:/usr/local/bin"

die() {
    echo -e "${red}错误: ${plain}$*" >&2
    exit 1
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
        apt-get update
        apt-get install -y "$@"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm "$@"
    else
        die "未找到受支持的软件包管理器"
    fi
}

install_base() {
    local packages=()
    command -v curl >/dev/null 2>&1 || packages+=(curl)
    command -v python3 >/dev/null 2>&1 || packages+=(python3)
    if [[ ${#packages[@]} -gt 0 ]]; then
        install_soft "${packages[@]}"
    fi
}

download_file() {
    local url="$1" destination="$2"
    if ! curl --fail --show-error --silent --location \
        --retry 3 --connect-timeout 10 --output "$destination" "$url"; then
        die "文件下载失败：${url}"
    fi
    [[ -s "$destination" ]] || die "下载文件为空：${url}"
}

validate_config() {
    local host="$1" user="$2" pass="$3"
    [[ "$host" =~ ^[A-Za-z0-9._:-]+$ ]] || die "服务端地址格式无效"
    [[ "$user" =~ ^[A-Za-z0-9_-]+$ ]] || die "节点用户名格式无效"
    [[ "$pass" =~ ^[A-Za-z0-9_-]+$ ]] || die "节点密码格式无效"
}

install_agent() {
    local host="$1" user="$2" pass="$3" stage
    validate_config "$host" "$user" "$pass"
    install_base

    stage=$(mktemp -d)
    trap 'rm -rf -- "$stage"' EXIT

    echo "> 下载并安装 Agent"
    download_file "${GITHUB_RAW_URL}/agent/client-linux.py" "${stage}/client-linux.py"
    download_file "${GITHUB_RAW_URL}/agent/sss-agent.service" "${stage}/sss-agent.service"

    install -d -m 0755 "$SSS_AGENT_PATH"
    install -m 0755 "${stage}/client-linux.py" "${SSS_AGENT_PATH}/client-linux.py"
    install -m 0644 "${stage}/sss-agent.service" "$SSS_AGENT_SERVICE"

    {
        printf 'SSS_SERVER=%s\n' "$host"
        printf 'SSS_USER=%s\n' "$user"
        printf 'SSS_PASSWORD=%s\n' "$pass"
        printf 'SSS_PORT=35601\n'
        printf 'SSS_INTERVAL=1\n'
    } > "${stage}/sss-agent.env"
    install -m 0600 "${stage}/sss-agent.env" "$SSS_AGENT_ENV"

    systemctl daemon-reload
    systemctl enable --now sss-agent
    if ! systemctl is-active --quiet sss-agent; then
        systemctl status sss-agent --no-pager || true
        die "Agent 启动失败"
    fi

    rm -rf -- "$stage"
    trap - EXIT
    echo -e "${green}Agent 安装成功${plain}"
}

prompt_install() {
    local host user pass
    read -r -p "ServerStatus 服务端地址: " host
    read -r -p "节点用户名: " user
    read -r -s -p "节点密码: " pass
    echo
    install_agent "$host" "$user" "$pass"
}

uninstall_agent() {
    systemctl stop sss-agent >/dev/null 2>&1 || true
    systemctl disable sss-agent >/dev/null 2>&1 || true
    rm -rf -- "$SSS_AGENT_PATH"
    rm -f -- "$SSS_AGENT_SERVICE" "$SSS_AGENT_ENV"
    systemctl daemon-reload
}

show_menu() {
    local num
    echo -e "
    ${green}Server Status 监控管理脚本${plain}
    ${green}1.${plain} 安装或更新 Agent
    ${green}2.${plain} 卸载 Agent
    ${green}0.${plain} 退出脚本
    "
    read -r -p "请输入选择 [0-2]: " num
    case "$num" in
        0) exit 0 ;;
        1) prompt_install ;;
        2) uninstall_agent; echo -e "${green}卸载 Agent 完成${plain}" ;;
        *) die "请输入正确的数字 [0-2]" ;;
    esac
}

usage() {
    echo "用法："
    echo "  sudo ./sss-agent.sh install <服务端地址> <节点用户名>"
    echo "  sudo ./sss-agent.sh uninstall"
    echo "  sudo ./sss-agent.sh <服务端地址> <节点用户名> <节点密码>  # 兼容旧用法"
}

pre_check

case "${1:-}" in
    install)
        [[ $# -eq 3 ]] || { usage; exit 1; }
        host="$2"
        user="$3"
        read -r -s -p "节点密码: " pass
        echo
        install_agent "$host" "$user" "$pass"
        ;;
    uninstall)
        [[ $# -eq 1 ]] || { usage; exit 1; }
        uninstall_agent
        echo -e "${green}卸载 Agent 完成${plain}"
        ;;
    '')
        show_menu
        ;;
    *)
        if [[ $# -eq 3 ]]; then
            echo -e "${yellow}提示：旧式参数会把密码留在 Shell 历史中，建议改用 install 子命令。${plain}"
            install_agent "$1" "$2" "$3"
        else
            usage
            exit 1
        fi
        ;;
esac
