#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir "${test_root}/tmp"
export TMPDIR="${test_root}/tmp"

cd "$test_root"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' '{"servers":[{"name":"keep-config"}]}' > config.json
printf '%s\n' 'KEEP_ENV=1' > .env
mkdir -p json
printf '%s\n' '{"servers":[{"name":"keep-stats"}]}' > json/stats.json

sed '/^# ================= 入口 =================$/,$d' "${repo_root}/sss.sh" > sss-definitions.sh
source sss-definitions.sh

mkdir node-install-view
cd node-install-view
printf '%s\n' '{"servers":[{"name":"rebuild-node","location":"us","type":"kvm","username":"node-user","password":"node-password"}]}' > config.json
CONFIG_FILE=config.json
get_ip() { printf '%s' '203.0.113.10'; }
install_output=$(printf '0\n' | show_node_install)
grep -q '重新安装 agent 服务' <<< "$install_output"
grep -q 'sss-agent.sh install 203.0.113.10 node-user' <<< "$install_output"
grep -q '节点密码（安装时粘贴）: node-password' <<< "$install_output"
cd "$test_root"

file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

mkdir self-update-test
printf '%s\n' '#!/bin/bash' 'printf old' > self-update-test/current.sh
printf '%s\n' '#!/bin/bash' 'printf new' > self-update-test/candidate.sh
self_update_candidate="${test_root}/self-update-test/candidate.sh"
download_file_definition=$(declare -f download_file)
download_file() { install -m 0644 "$self_update_candidate" "$2"; }
update_script_file self-update-test/current.sh
cmp -s self-update-test/current.sh self-update-test/candidate.sh
[[ $(file_mode self-update-test/current.sh) == 755 ]]
if update_script_file self-update-test/current.sh; then
    exit 1
fi
printf '%s\n' '#!/bin/bash' 'broken (' > self-update-test/candidate.sh
set +e
(update_script_file self-update-test/current.sh) >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 1 ]]
grep -qx 'printf new' self-update-test/current.sh
eval "$download_file_definition"

docker() {
    case "$*" in
        "compose version") return 0 ;;
        "compose up --help") printf '%s\n' 'Usage: up --wait --wait-timeout' ;;
        "compose ps --help") printf '%s\n' 'Usage: ps --status' ;;
        *) return 1 ;;
    esac
}
COMPOSE_CMD=()
detect_compose
[[ "${COMPOSE_CMD[*]}" == "docker compose" ]]
docker() {
    case "$*" in
        "compose version") return 0 ;;
        "compose up --help") printf '%s\n' 'Usage: up --wait-timeout' ;;
        "compose ps --help") printf '%s\n' 'Usage: ps --status' ;;
        *) return 1 ;;
    esac
}
COMPOSE_CMD=()
if detect_compose; then
    exit 1
fi
set +e
(
    docker() {
        case "$*" in
            "compose version") return 0 ;;
            "compose up --help") printf '%s\n' 'Usage: up --wait-timeout' ;;
            "compose ps --help") printf '%s\n' 'Usage: ps --status' ;;
            *) return 1 ;;
        esac
    }
    install_base() { :; }
    install_soft() { :; }
    info() { :; }
    die() { printf '%s\n' "$*"; exit 1; }
    install_docker
) > capability-error.log
status=$?
set -e
[[ $status -eq 1 ]]
grep -q '需要 docker compose up --wait/--wait-timeout 和 docker compose ps --status' capability-error.log
docker() { return 1; }
COMPOSE_CMD=()
if detect_compose; then
    exit 1
fi
if sed -n '/^detect_compose()/,/^}/p' sss-definitions.sh | grep -q 'docker-compose'; then
    exit 1
fi
grep -q 'Docker Compose v2 插件' sss-definitions.sh
grep -q 'up --wait/--wait-timeout' sss-definitions.sh
grep -q 'ps --status' sss-definitions.sh
if configure_bot bot-env invalid-argument >/dev/null 2>&1; then
    exit 1
fi

mkdir configure-candidate
cd configure-candidate
printf '%s\n' 'KEEP_ENV=1' > .env
configure_bot env.next 123 '456:token' >/dev/null
grep -qx 'KEEP_ENV=1' .env
grep -qx 'KEEP_ENV=1' env.next
grep -qx 'TG_BOT_TOKEN=456:token' env.next
[[ -z "$CONFIGURE_BOT_STAGE" ]]
cd "$test_root"

mkdir signal-configure-stage signal-install-stage
printf '%s\n' 'secret' > signal-configure-stage/env
set +e
(
    CONFIGURE_BOT_STAGE="${test_root}/signal-configure-stage"
    INSTALL_STAGE="${test_root}/signal-install-stage"
    INSTALL_HAD_PREVIOUS_COMPOSE=0
    INSTALL_HAD_PREVIOUS_ENV=0
    INSTALL_ENV_MAY_BE_REPLACED=0
    INSTALL_COMPOSE_MAY_BE_REPLACED=0
    INSTALL_STACK_TOUCHED=0
    install_signal_handler TERM
) >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 143 ]]
[[ ! -e signal-configure-stage && ! -e signal-install-stage ]]

mkdir atomic-test
printf '%s\n' 'old-atomic-content' > atomic-test/destination
printf '%s\n' 'new-atomic-content' > atomic-test/source
chmod 0500 atomic-test
if atomic_replace atomic-test/source atomic-test/destination 0644 2>/dev/null; then
    exit 1
fi
chmod 0700 atomic-test
grep -qx 'old-atomic-content' atomic-test/destination

eval "$(declare -f atomic_replace | sed '1s/^atomic_replace/atomic_replace_original/')"
atomic_replace() {
    local source="$1" destination="$2"
    if [[ "${FAIL_COMPOSE_REPLACE:-0}" -eq 1 && "$source" == */docker-compose.yml && "$destination" == docker-compose.yml ]]; then
        return 1
    fi
    atomic_replace_original "$@" || return 1
    if [[ "${SIGNAL_AT:-}" == "atomic-compose" && "$source" == */docker-compose.yml && "$destination" == docker-compose.yml && ! -e atomic-signal-fired ]]; then
        printf '%s\n' fired > atomic-signal-fired
        printf '%s\n' "$INSTALL_STAGE" > signal-stage-path
        printf '%s\n' ready > signal-ready
        while :; do
            sleep 1
        done
    fi
    return 0
}

FORCE_INSTALL=1
CONFIG_FILE=config.json
install_docker() { :; }
configure_bot() {
    destination="$1"
    shift
    if [[ "${FAIL_CONFIGURE_BOT:-0}" -eq 1 ]]; then
        printf '%s\n' 'NEW_ENV=1' > "$destination"
        return 1
    fi
    if [[ $# -gt 0 ]]; then
        printf '%s\n' 'NEW_ENV=1' > "$destination"
    elif [[ -f .env ]]; then
        install -m 0600 .env "$destination"
    else
        rm -f -- "$destination"
    fi
}
step() {
    if [[ "${SIGNAL_AT:-}" == "before-up" && ${INSTALL_COMPOSE_MAY_BE_REPLACED:-0} -eq 1 ]]; then
        printf '%s\n' "$INSTALL_STAGE" > signal-stage-path
        printf '%s\n' ready > signal-ready
        while :; do
            sleep 1
        done
    fi
}
warn() { :; }
ok() { :; }
err() { printf '%s\n' "$*" >> installer-errors.log; }
download_file() { install -m 0644 "${repo_root}/docker-compose.yml" "$2"; }
compose_file() {
    printf 'staged %s\n' "$*" >> compose-calls.log
    if [[ "$*" == *" pull"* && -f docker-compose.yml ]]; then
        grep -qx 'old-compose-marker' docker-compose.yml
    fi
    if [[ "$*" == *" pull"* && "${FAIL_STAGED_PULL:-0}" -eq 1 ]]; then
        return 1
    fi
    if [[ "$*" == *" pull"* && "${SIGNAL_AT:-}" == "pull" ]]; then
        dirname -- "$1" > signal-stage-path
        install_signal_handler TERM
    fi
}
compose() {
    printf 'active %s\n' "$*" >> compose-calls.log
    if [[ "$*" == "up -d --wait --wait-timeout 90" && "${SIGNAL_AT:-}" == "up" ]]; then
        printf '%s\n' "$INSTALL_STAGE" > signal-stage-path
        install_signal_handler TERM
    fi
    if [[ "$1" == "up" ]] && grep -q 'ghcr.io/lau0x/serverstatus-web@sha256:' docker-compose.yml; then
        [[ "${ALLOW_NEW_UP:-0}" -eq 1 ]] && return 0
        return 1
    fi
    if [[ "$1" == "up" && "${FAIL_OLD_UP:-0}" -eq 1 ]]; then
        return 1
    fi
}
die() {
    printf '%s\n' "$*" > installer-error.log
    exit 1
}

set +e
(install_dashboard 123 '456:token')
status=$?
set -e

[[ $status -eq 1 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -q 'keep-config' config.json
grep -q 'keep-stats' json/stats.json
grep -qx 'KEEP_ENV=1' .env
grep -q 'staged .* config --quiet' compose-calls.log
grep -q 'staged .* pull' compose-calls.log
[[ $(grep -c '^active up -d --wait --wait-timeout 90$' compose-calls.log) -eq 1 ]]
[[ $(grep -c '^active up -d$' compose-calls.log) -eq 1 ]]
grep -q '^active down$' compose-calls.log
grep -q '已恢复旧 Compose 并重新启动旧栈' installer-error.log

mkdir "${test_root}/new-install"
cd "${test_root}/new-install"

set +e
(install_dashboard)
status=$?
set -e

[[ $status -eq 1 ]]
grep -q '^active down$' compose-calls.log
grep -q '^active up -d --wait --wait-timeout 90$' compose-calls.log
grep -q '首次安装启动失败，新栈和新 Compose 已清理' installer-error.log
[[ ! -e docker-compose.yml ]]
grep -qx '{"servers":\[\]}' config.json
grep -qx '{"servers":\[\],"sslcerts":\[\]}' json/stats.json
[[ ! -e .env ]]

mkdir "${test_root}/compose-replace-failure"
cd "${test_root}/compose-replace-failure"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' '{"servers":[]}' > config.json
mkdir json
printf '%s\n' '{"servers":[]}' > json/stats.json
: > compose-calls.log
: > installer-error.log
FAIL_COMPOSE_REPLACE=1
SIGNAL_AT=

set +e
(install_dashboard)
status=$?
set -e

[[ $status -eq 1 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -q '原子替换 Compose 失败，原部署已恢复' installer-error.log
if grep -q '^active ' compose-calls.log; then
    exit 1
fi
FAIL_COMPOSE_REPLACE=0

mkdir "${test_root}/staged-pull-failure"
cd "${test_root}/staged-pull-failure"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[{"name":"keep-config"}]}' > config.json
mkdir json
printf '%s\n' '{"servers":[{"name":"keep-stats"}]}' > json/stats.json
FAIL_STAGED_PULL=1

set +e
(install_dashboard 123 '456:token')
status=$?
set -e

[[ $status -eq 1 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -qx 'KEEP_ENV=1' .env
grep -q 'keep-config' config.json
grep -q 'keep-stats' json/stats.json
grep -q '新镜像拉取失败，现有部署未修改' installer-error.log
if grep -q '^active ' compose-calls.log; then
    exit 1
fi

mkdir "${test_root}/signal-during-pull"
cd "${test_root}/signal-during-pull"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[{"name":"keep-config"}]}' > config.json
mkdir json
printf '%s\n' '{"servers":[{"name":"keep-stats"}]}' > json/stats.json
FAIL_STAGED_PULL=0
SIGNAL_AT=pull

set +e
(install_dashboard 123 '456:token')
status=$?
set -e

[[ $status -eq 143 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -qx 'KEEP_ENV=1' .env
grep -q 'keep-config' config.json
grep -q 'keep-stats' json/stats.json
signal_stage=$(cat signal-stage-path)
[[ ! -e "$signal_stage" ]]
grep -q '安装被 TERM 信号中断，原部署已恢复' installer-errors.log
if grep -q '^active ' compose-calls.log; then
    exit 1
fi

mkdir "${test_root}/signal-after-compose-mv"
cd "${test_root}/signal-after-compose-mv"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[{"name":"keep-config"}]}' > config.json
mkdir json
printf '%s\n' '{"servers":[{"name":"keep-stats"}]}' > json/stats.json
SIGNAL_AT=atomic-compose

(install_dashboard 123 '456:token') &
install_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -f signal-ready ]] && break
    sleep 0.05
done
if [[ ! -f signal-ready ]]; then
    kill -TERM "$install_pid" 2>/dev/null || true
    wait "$install_pid" 2>/dev/null || true
    exit 1
fi
kill -TERM "$install_pid"
set +e
wait "$install_pid"
status=$?
set -e

[[ $status -eq 143 ]]
[[ -f atomic-signal-fired ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -qx 'KEEP_ENV=1' .env
grep -q 'keep-config' config.json
grep -q 'keep-stats' json/stats.json
signal_stage=$(cat signal-stage-path)
[[ ! -e "$signal_stage" ]]
grep -q '安装被 TERM 信号中断，原部署已恢复' installer-errors.log
if [[ -f compose-calls.log ]] && grep -q '^active ' compose-calls.log; then
    exit 1
fi

mkdir "${test_root}/signal-after-compose-replace"
cd "${test_root}/signal-after-compose-replace"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[{"name":"keep-config"}]}' > config.json
mkdir json
printf '%s\n' '{"servers":[{"name":"keep-stats"}]}' > json/stats.json
SIGNAL_AT=before-up

(install_dashboard 123 '456:token') &
install_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -f signal-ready ]] && break
    sleep 0.05
done
if [[ ! -f signal-ready ]]; then
    kill -TERM "$install_pid" 2>/dev/null || true
    wait "$install_pid" 2>/dev/null || true
    exit 1
fi
kill -TERM "$install_pid"
set +e
wait "$install_pid"
status=$?
set -e

[[ $status -eq 143 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -qx 'KEEP_ENV=1' .env
grep -q 'keep-config' config.json
grep -q 'keep-stats' json/stats.json
signal_stage=$(cat signal-stage-path)
[[ ! -e "$signal_stage" ]]
grep -q '安装被 TERM 信号中断，原部署已恢复' installer-errors.log
if [[ -f compose-calls.log ]] && grep -q '^active ' compose-calls.log; then
    exit 1
fi

mkdir "${test_root}/signal-during-upgrade"
cd "${test_root}/signal-during-upgrade"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[{"name":"keep-config"}]}' > config.json
mkdir json
printf '%s\n' '{"servers":[{"name":"keep-stats"}]}' > json/stats.json
SIGNAL_AT=up
FAIL_OLD_UP=0

set +e
(install_dashboard 123 '456:token')
status=$?
set -e

[[ $status -eq 143 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -qx 'KEEP_ENV=1' .env
grep -q 'keep-config' config.json
grep -q 'keep-stats' json/stats.json
signal_stage=$(cat signal-stage-path)
[[ ! -e "$signal_stage" ]]
grep -q '^active down$' compose-calls.log
grep -q '^active up -d$' compose-calls.log
grep -q '安装被 TERM 信号中断，原部署已恢复' installer-errors.log

mkdir "${test_root}/signal-during-first-install"
cd "${test_root}/signal-during-first-install"
SIGNAL_AT=up

set +e
(install_dashboard)
status=$?
set -e

[[ $status -eq 143 ]]
[[ ! -e docker-compose.yml && ! -e .env ]]
grep -qx '{"servers":\[\]}' config.json
grep -qx '{"servers":\[\],"sslcerts":\[\]}' json/stats.json
signal_stage=$(cat signal-stage-path)
[[ ! -e "$signal_stage" ]]
grep -q '^active down$' compose-calls.log
grep -q '安装被 TERM 信号中断，原部署已恢复' installer-errors.log

mkdir "${test_root}/configure-failure"
cd "${test_root}/configure-failure"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[]}' > config.json
mkdir json
printf '%s\n' '{"servers":[]}' > json/stats.json
FAIL_STAGED_PULL=0
FAIL_CONFIGURE_BOT=1
SIGNAL_AT=

set +e
(install_dashboard 123 '456:token')
status=$?
set -e

[[ $status -eq 1 ]]
grep -qx 'old-compose-marker' docker-compose.yml
grep -qx 'KEEP_ENV=1' .env
grep -q 'Telegram 配置失败，原 .env 未修改' installer-error.log
[[ ! -e compose-calls.log ]]

mkdir "${test_root}/successful-install"
cd "${test_root}/successful-install"
FAIL_CONFIGURE_BOT=0
ALLOW_NEW_UP=1

install_dashboard

grep -q 'ghcr.io/lau0x/serverstatus-web@sha256:' docker-compose.yml
grep -qx '{"servers":\[\]}' config.json
grep -qx '{"servers":\[\],"sslcerts":\[\]}' json/stats.json
grep -q '^active up -d --wait --wait-timeout 90$' compose-calls.log
if grep -q '^active down$' compose-calls.log; then
    exit 1
fi

mkdir "${test_root}/failed-old-stack-restore"
cd "${test_root}/failed-old-stack-restore"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' '{"servers":[]}' > config.json
mkdir json
printf '%s\n' '{"servers":[]}' > json/stats.json
ALLOW_NEW_UP=0
FAIL_OLD_UP=1

set +e
(install_dashboard)
status=$?
set -e

[[ $status -eq 1 ]]
backup_path=$(sed -n 's/.*备份保留在 //p' installer-error.log)
[[ -n "$backup_path" && -d "$backup_path" ]]
[[ $(file_mode "$backup_path") == 700 ]]
grep -qx 'old-compose-marker' "$backup_path/docker-compose.yml.previous"
grep -q '旧栈自动恢复未完全成功；暂存与备份保留在' installer-error.log

mkdir "${test_root}/signal-restore-failure"
cd "${test_root}/signal-restore-failure"
printf '%s\n' 'old-compose-marker' > docker-compose.yml
printf '%s\n' 'KEEP_ENV=1' > .env
printf '%s\n' '{"servers":[]}' > config.json
mkdir json
printf '%s\n' '{"servers":[]}' > json/stats.json
SIGNAL_AT=up
FAIL_OLD_UP=1

set +e
(install_dashboard)
status=$?
set -e

[[ $status -eq 143 ]]
signal_stage=$(cat signal-stage-path)
[[ -d "$signal_stage" ]]
[[ $(file_mode "$signal_stage") == 700 ]]
grep -qx 'old-compose-marker' "$signal_stage/docker-compose.yml.previous"
grep -q "暂存与备份保留在 ${signal_stage}" installer-errors.log
