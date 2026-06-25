#!/bin/bash

# sync_soga_cert1.sh
# 从主服务器同步 vowa88.top 证书到 /etc/soga3。

MASTER_IP="131.186.1.95"
MASTER_PORT="22"
MASTER_PASS="n4Vzg74PysnXNV3"
SYNC_DIR="/etc/soga3/"
LOG_FILE="/var/log/soga_cert_sync1.log"
SCRIPT_PATH="/root/sync_soga_cert1.sh"
SERVICE_NAME="soga3"
SOGA_BIN="/usr/local/soga/soga"
SOGA_CONFIG="${SYNC_DIR}soga.conf"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

ensure_cron_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now cron >/dev/null 2>&1 || true
    else
        service cron start >/dev/null 2>&1 || true
    fi
}

write_cron_without_old_sync_jobs() {
    output_file="$1"

    crontab -l 2>/dev/null \
        | grep -v 'sync_soga_cert' \
        > "$output_file" || true
}

install_cron() {
    tmp_cron="$(mktemp)"
    random_minute=$((RANDOM % 60))

    write_cron_without_old_sync_jobs "$tmp_cron"

    echo "$random_minute 3 1,15 * * $SCRIPT_PATH > /dev/null 2>&1" >> "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"

    echo "定时任务已安装：每月 1 号和 15 号，凌晨 03:00-03:59 随机执行，本机分钟数为 $random_minute。"
}

setup_env() {
    echo "正在检查并更新系统环境..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update && apt-get install -y cron sshpass rsync openssh-client screen
    mkdir -p "$SYNC_DIR"

    if [ -f "$SCRIPT_PATH" ]; then
        chmod +x "$SCRIPT_PATH" 2>/dev/null || true
    fi

    install_cron
    ensure_cron_service
}

restart_soga_instance() {
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
        systemctl restart "$SERVICE_NAME"
        return $?
    fi

    if [ ! -x "$SOGA_BIN" ]; then
        echo "未找到 soga 主程序：$SOGA_BIN"
        return 1
    fi

    if [ ! -f "$SOGA_CONFIG" ]; then
        echo "未找到配置文件：$SOGA_CONFIG"
        return 1
    fi

    if screen -list 2>/dev/null | grep -qw "$SERVICE_NAME"; then
        screen -S "$SERVICE_NAME" -X quit 2>/dev/null || true
        sleep 2
    fi

    if screen -list 2>/dev/null | grep -qw "$SERVICE_NAME"; then
        screen -S "$SERVICE_NAME" -X kill 2>/dev/null || true
        sleep 1
    fi

    screen -dmS "$SERVICE_NAME" "$SOGA_BIN" -c "$SOGA_CONFIG"
    sleep 2

    screen -list 2>/dev/null | grep -qw "$SERVICE_NAME"
}

do_sync() {
    setup_env

    echo "正在同步证书..."

    if sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no \
        "root@$MASTER_IP:/etc/soga/vowa88.top.crt" "${SYNC_DIR}vowa88.top.crt" \
        && sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no \
        "root@$MASTER_IP:/etc/soga/vowa88.top.key" "${SYNC_DIR}vowa88.top.key"; then

        chmod 644 "${SYNC_DIR}vowa88.top.crt" 2>/dev/null || true
        chmod 600 "${SYNC_DIR}vowa88.top.key" 2>/dev/null || true

        if restart_soga_instance; then
            log_msg "同步成功"
            echo "同步成功，并已重启 $SERVICE_NAME。"
        else
            log_msg "证书已复制，但重启 $SERVICE_NAME 失败"
            echo "证书已复制，但重启 $SERVICE_NAME 失败。"
            return 1
        fi
    else
        log_msg "同步失败"
        echo "同步失败，请检查网络、主服务器或密码。"
        return 1
    fi
}

show_menu() {
    echo "--- 证书同步管理系统 ---"
    echo "1) 同步证书，并更新环境/定时任务"
    echo "2) 查看同步频率"
    echo "3) 修改同步频率（输入天数）"
    echo "4) 查看同步日志"
    read -r -p "请选择（默认1）: " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            do_sync
            ;;
        2)
            echo "当前定时任务为："
            crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH" || echo "未找到定时任务。"
            ;;
        3)
            read -r -p "请输入同步间隔（天）: " days
            if ! echo "$days" | grep -Eq '^[0-9]+$' || [ "$days" -lt 1 ]; then
                echo "同步间隔无效。"
                return 1
            fi
            tmp_cron="$(mktemp)"
            random_minute=$((RANDOM % 60))
            write_cron_without_old_sync_jobs "$tmp_cron"
            echo "$random_minute 3 */$days * * $SCRIPT_PATH > /dev/null 2>&1" >> "$tmp_cron"
            crontab "$tmp_cron"
            rm -f "$tmp_cron"
            echo "已设置为每 $days 天同步一次，凌晨 03:00-03:59 随机执行，本机分钟数为 $random_minute。"
            ;;
        4)
            [ -f "$LOG_FILE" ] && tail -n 20 "$LOG_FILE" || echo "暂无同步日志。"
            ;;
        *)
            echo "无效选择。"
            return 1
            ;;
    esac
}

if [ -t 0 ]; then
    show_menu
else
    do_sync
fi
