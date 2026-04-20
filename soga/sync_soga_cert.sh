#!/bin/bash

# --- 请在此处填写主服务器信息 ---
MASTER_IP="131.186.1.95"
MASTER_PORT="22"
MASTER_PASS="n4Vzg74PysnXNV3"
# ------------------------------

# 1. 安装 sshpass 和 rsync
echo "正在安装同步工具..."
apt update && apt install -y sshpass rsync

# 2. 确保本地目标目录 /etc/soga3/ 存在
mkdir -p /etc/soga3/

# 3. 创建同步脚本
cat <<EOF > /root/sync_soga_cert.sh
#!/bin/bash
# 从主服务器同步证书到本地 /etc/soga3/
sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no root@$MASTER_IP:/etc/soga/mexta.click.crt /etc/soga3/mexta.click.crt
sshpass -p "$MASTER_PASS" scp -P "$MASTER_PORT" -o StrictHostKeyChecking=no root@$MASTER_IP:/etc/soga/mexta.click.key /etc/soga3/mexta.click.key

# 重启 Soga 服务 (确保 Soga 是从 /etc/soga3/ 读取证书的)
systemctl restart soga
EOF

# 4. 给脚本赋予执行权限
chmod +x /root/sync_soga_cert.sh

# 5. 设置定时任务 (每月 1 号凌晨 3 点执行)
(crontab -l 2>/dev/null | grep -v "sync_soga_cert.sh"; echo "0 3 1 * * /root/sync_soga_cert.sh > /dev/null 2>&1") | crontab -

echo "==========================================="
echo "同步脚本已安装完毕！"
echo "主服务器路径: /etc/soga/"
echo "本地同步路径: /etc/soga3/"
echo "同步时间: 每月 1 号凌晨 3 点"
echo "==========================================="

# 立即执行一次测试
bash /root/sync_soga_cert.sh
echo "已触发首次同步，请检查 /etc/soga3/ 下是否有文件。"
