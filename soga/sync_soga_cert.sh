#!/bin/bash

# --- 默认配置 ---
MASTER_IP="131.186.1.95"
MASTER_PORT="22"
MASTER_PASS="n4Vzg74PysnXNV3"
SYNC_DIR="/etc/soga3/"
LOG_FILE="/var/log/soga_cert_sync.log"
CRON_FILE="/root/sync_soga_cert.sh"

# 确保环境
apt update && apt install -y sshpass rsync

# 同步核心函数
do_sync() {
    echo "正在同步证书..."
    sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no root@$MASTER_IP:/etc/soga/vowa88.top.crt ${SYNC_DIR}vowa88.top.crt
    sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no root@$MASTER_IP:/etc/soga/vowa88.top.key ${SYNC_DIR}vowa88.top.key
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 同步成功" >> $LOG_FILE
        systemctl restart soga
        echo "同步并重启 Soga 成功。"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 同步失败" >> $LOG_FILE
        echo "同步失败，请检查网络或密码。"
    fi
}

echo "1) 同步证书"
echo "2) 查看同步频率"
echo "3) 修改同步频率 (输入天数)"
echo "4) 查看同步日志"
read -p "请选择 (默认1): " choice
choice=${choice:-1}

case $choice in
    1) do_sync ;;
    2) echo "当前定时任务为:" && crontab -l | grep "sync_soga_cert.sh" ;;
    3) 
        read -p "请输入同步间隔(天): " days
        # 这里使用 cron 的 @daily 或者 */X * * * * 逻辑
        (crontab -l 2>/dev/null | grep -v "sync_soga_cert.sh"; echo "0 3 */$days * * /root/sync_soga_cert.sh > /dev/null 2>&1") | crontab -
        echo "已设置为每 $days 天同步一次。" 
        ;;
    4) [ -f "$LOG_FILE" ] && tail -n 20 $LOG_FILE || echo "暂无日志。" ;;
    *) echo "无效选择" ;;
esac
