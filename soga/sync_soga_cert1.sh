#!/bin/bash

# sync_soga_cert1.sh
# Sync vowa88.top cert files from the master server to /etc/soga3.

MASTER_IP="131.186.1.95"
MASTER_PORT="22"
MASTER_PASS="n4Vzg74PysnXNV3"
SYNC_DIR="/etc/soga3/"
LOG_FILE="/var/log/soga_cert_sync1.log"
SCRIPT_PATH="/root/sync_soga_cert1.sh"
SERVICE_NAME="soga3"

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

    echo "Cron installed: day 1 and 15, between 03:00 and 04:00, minute $random_minute."
}

setup_env() {
    echo "Checking environment..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update && apt-get install -y cron sshpass rsync openssh-client
    mkdir -p "$SYNC_DIR"

    if [ -f "$SCRIPT_PATH" ]; then
        chmod +x "$SCRIPT_PATH" 2>/dev/null || true
    fi

    install_cron
    ensure_cron_service
}

do_sync() {
    setup_env

    echo "Syncing certificate..."

    if sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no \
        "root@$MASTER_IP:/etc/soga/vowa88.top.crt" "${SYNC_DIR}vowa88.top.crt" \
        && sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no \
        "root@$MASTER_IP:/etc/soga/vowa88.top.key" "${SYNC_DIR}vowa88.top.key"; then

        chmod 644 "${SYNC_DIR}vowa88.top.crt" 2>/dev/null || true
        chmod 600 "${SYNC_DIR}vowa88.top.key" 2>/dev/null || true

        if systemctl restart "$SERVICE_NAME"; then
            log_msg "sync success"
            echo "Sync succeeded and $SERVICE_NAME restarted."
        else
            log_msg "sync copied files but failed to restart $SERVICE_NAME"
            echo "Files copied, but $SERVICE_NAME restart failed."
            return 1
        fi
    else
        log_msg "sync failed"
        echo "Sync failed. Check network, master server, or password."
        return 1
    fi
}

show_menu() {
    echo "--- Certificate Sync Manager ---"
    echo "1) Sync certificate and update environment/cron"
    echo "2) Show sync schedule"
    echo "3) Change sync interval by days"
    echo "4) Show sync log"
    read -r -p "Choose (default 1): " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            do_sync
            ;;
        2)
            echo "Current scheduled task:"
            crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH" || echo "No scheduled task found."
            ;;
        3)
            read -r -p "Enter sync interval in days: " days
            if ! echo "$days" | grep -Eq '^[0-9]+$' || [ "$days" -lt 1 ]; then
                echo "Invalid day interval."
                return 1
            fi
            tmp_cron="$(mktemp)"
            random_minute=$((RANDOM % 60))
            write_cron_without_old_sync_jobs "$tmp_cron"
            echo "$random_minute 3 */$days * * $SCRIPT_PATH > /dev/null 2>&1" >> "$tmp_cron"
            crontab "$tmp_cron"
            rm -f "$tmp_cron"
            echo "Sync schedule changed to every $days day(s), between 03:00 and 04:00, minute $random_minute."
            ;;
        4)
            [ -f "$LOG_FILE" ] && tail -n 20 "$LOG_FILE" || echo "No sync log yet."
            ;;
        *)
            echo "Invalid choice."
            return 1
            ;;
    esac
}

if [ -t 0 ]; then
    show_menu
else
    do_sync
fi
