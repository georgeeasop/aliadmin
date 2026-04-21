#!/bin/bash

set -e

echo "===> 创建目录并下载证书..."

mkdir -p /etc/soga4

wget -O /etc/soga3/mexta.click.crt https://github.com/georgeeasop/aliadmin/raw/refs/heads/main/mexta.click.crt
wget -O /etc/soga3/mexta.click.key https://github.com/georgeeasop/aliadmin/raw/refs/heads/main/mexta.click.key

chmod 644 /etc/soga3/mexta.click.crt
chmod 600 /etc/soga3/mexta.click.key

echo "===> 证书下载完成"

CONFIG_FILE="/etc/soga3/soga.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

echo "===> 修改配置文件..."

# 删除旧的 dns 相关配置
sed -i '/cert_mode=dns/d' $CONFIG_FILE
sed -i '/cert_key_length=/d' $CONFIG_FILE
sed -i '/dns_provider=/d' $CONFIG_FILE
sed -i '/DNS_CF_Email=/d' $CONFIG_FILE
sed -i '/DNS_CF_Key=/d' $CONFIG_FILE

# 删除旧的 cert_mode（防止重复）
sed -i '/cert_mode=/d' $CONFIG_FILE
sed -i '/cert_file=/d' $CONFIG_FILE
sed -i '/key_file=/d' $CONFIG_FILE

# 在 cert_domain 后面插入新配置
sed -i '/cert_domain=/a cert_mode=file\ncert_file=/etc/soga3/mexta.click.crt\nkey_file=/etc/soga4/mexta.click.key' $CONFIG_FILE

echo "===> 配置修改完成"

echo "✅ 全部完成！"
