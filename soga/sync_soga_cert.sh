#!/bin/bash

# --- 默认配置 ---
MASTER_IP="131.186.1.95"
MASTER_PORT="22"
MASTER_PASS="n4Vzg74PysnXNV3"
SYNC_DIR="/etc/soga3/"
LOG_FILE="/var/log/soga_cert_sync.log"
SCRIPT_PATH="/root/sync_soga_cert.sh"

# 环境检查与安装函数
setup_env() {
    echo "正在检查并更新系统环境..."
    apt update && apt install -y sshpass rsync
    # 确保定时任务存在 (默认每 1 天同步一次)
    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        (crontab -l 2>/dev/null; echo "0 3 */1 * * $SCRIPT_PATH > /dev/null 2>&1") | crontab -
    fi
}

# 同步核心函数
do_sync() {
    setup_env
    echo "正在同步证书..."
    sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no root@$MASTER_IP:/etc/soga/mexta.click.crt ${SYNC_DIR}mexta.click.crt
    sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no root@$MASTER_IP:/etc/soga/mexta.click.key ${SYNC_DIR}mexta.click.key
    
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 同步成功" >> $LOG_FILE
        systemctl restart soga
        echo "同步并重启 Soga 成功。"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 同步失败" >> $LOG_FILE
        echo "同步失败，请检查网络或密码。"
    fi
}

# 菜单显示
echo "--- 证书同步管理系统 ---"
echo "1) 同步证书 (并更新环境/任务)"
echo "2) 查看同步频率"
echo "3) 修改同步频率 (输入天数)"
echo "4) 查看同步日志"
read -p "请选择 (默认1): " choice
choice=${choice:-1}

case $choice in
    1) do_sync ;;
    2) 
        echo "当前定时任务为:" 
        crontab -l | grep "sync_soga_cert.sh" || echo "未找到定时任务。"
        ;;
    3) 
        read -p "请输入同步间隔(天): " days
        (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "0 3 */$days * * $SCRIPT_PATH > /dev/null 2>&1") | crontab -
        echo "已设置为每 $days 天同步一次。" 
        ;;
    4) 
        [ -f "$LOG_FILE" ] && tail -n 20 $LOG_FILE || echo "暂无同步日志。" 
        ;;
    *) echo "无效选择" ;;
esac
