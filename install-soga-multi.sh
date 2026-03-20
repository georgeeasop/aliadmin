#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

cur_dir=$(pwd)

# ========================================
# 默认配置参数（可在此处修改）
# ========================================

# soga 默认配置（除 node_id 外，node_id 需要用户输入）
SOGA_DEFAULT_TYPE="xboard"
SOGA_DEFAULT_SERVER_TYPE="ss"
SOGA_DEFAULT_SOGA_KEY=""
SOGA_DEFAULT_WEBAPI_URL=""
SOGA_DEFAULT_WEBAPI_KEY="M2X84M6a7N0iGHWC8fU7p8bwrVcCBmz"

# soga2 默认配置（除 node_id 外，node_id 需要用户输入）
SOGA2_DEFAULT_TYPE="xboard"
SOGA2_DEFAULT_SERVER_TYPE="ss"
SOGA2_DEFAULT_SOGA_KEY="HD7p1XpcTOLgaszkzg4fV2LgfZtYaIXK"
SOGA2_DEFAULT_WEBAPI_URL="https://mexta.top/"
SOGA2_DEFAULT_WEBAPI_KEY="1uU01fp9vUYZ7MrJdiSUee"

# ========================================

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    release="unknown"
fi

# 检测架构
arch=$(uname -m)
if [[ "$arch" == "x86_64" ]]; then
    arch="amd64"
elif [[ "$arch" == "aarch64" ]]; then
    arch="arm64"
else
    echo -e "${red}不支持的架构: ${arch}${plain}"
    exit 1
fi

echo "架构: ${arch}"

# 检查命令是否存在
is_cmd_exist() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查并安装 screen
check_and_install_screen() {
    if is_cmd_exist "screen"; then
        return 0
    fi
    
    echo -e "${yellow}screen 未安装，正在安装...${plain}"
    
    if [[ "$release" == "centos" ]]; then
        yum install -y screen
    elif [[ "$release" == "debian" ]] || [[ "$release" == "ubuntu" ]]; then
        apt-get update
        apt-get install -y screen
    else
        echo -e "${red}无法自动安装 screen，请手动安装${plain}"
        return 1
    fi
    
    if is_cmd_exist "screen"; then
        echo -e "${green}✓ screen 安装成功${plain}"
        return 0
    else
        echo -e "${red}screen 安装失败${plain}"
        return 1
    fi
}

# 检查实例是否已安装（兼容旧脚本的 systemd 方式和新脚本的 screen 方式）
is_instance_installed() {
    local instance_name=$1
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    # 检查配置目录是否存在（新脚本方式）
    if [[ -d "$config_dir" ]] && [[ -f "$config_dir/soga.conf" ]]; then
        return 0
    fi
    
    # 检查 systemd 服务是否存在（旧脚本方式）
    if [[ -f "/etc/systemd/system/${instance_name}.service" ]]; then
        return 0
    fi
    
    # 检查程序目录是否存在（旧脚本可能创建了）
    local soga_dir="/usr/local/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        soga_dir="/usr/local/soga"
    fi
    if [[ -d "$soga_dir" ]] && [[ -f "$soga_dir/soga" ]]; then
        return 0
    fi
    
    return 1
}

# 检查实例是否使用 systemd 运行
is_instance_using_systemd() {
    local instance_name=$1
    if [[ -f "/etc/systemd/system/${instance_name}.service" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查实例是否在运行（兼容 systemd 和 screen 方式）
is_instance_running() {
    local instance_name=$1
    
    # 检查 systemd 服务是否运行
    if is_instance_using_systemd ${instance_name}; then
        if systemctl is-active --quiet ${instance_name} 2>/dev/null; then
            return 0
        fi
    fi
    
    # 检查 screen 窗口是否运行
    if screen -list 2>/dev/null | grep -q "${instance_name}"; then
        return 0
    fi
    
    return 1
}

# 安装/更新 soga 主程序（所有实例共享）
install_soga_binary() {
    echo -e "${blue}========================================${plain}"
    echo -e "${green}安装/更新 soga 主程序${plain}"
    echo -e "${blue}========================================${plain}"
    
    # 检查是否已安装
    if [[ -f /usr/local/soga/soga ]]; then
        echo -e "${yellow}soga 主程序已存在，将更新到最新版${plain}"
    fi
    
    cd /usr/local/ || {
        echo -e "${red}无法切换到 /usr/local/ 目录${plain}"
        exit 1
    }
    
    # 下载 soga
    if [[ $# -le 0 ]] || [[ -z "$1" ]]; then
        echo -e "开始下载 soga 最新版"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz https://github.com/vaxilu/soga/releases/latest/download/soga-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 soga 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/vaxilu/soga/releases/download/${last_version}/soga-linux-${arch}.tar.gz"
        echo -e "开始下载 soga v$1"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 soga v$1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi
    
    # 使用临时目录解压
    local temp_extract_dir="soga_temp_extract_$$"
    echo -e "${yellow}解压到临时目录: ${temp_extract_dir}${plain}"
    
    mkdir -p ${temp_extract_dir} || {
        echo -e "${red}无法创建临时目录${plain}"
        exit 1
    }
    
    tar zxvf soga.tar.gz -C ${temp_extract_dir}
    if [[ $? -ne 0 ]]; then
        echo -e "${red}解压 soga 失败${plain}"
        rm -rf ${temp_extract_dir}
        exit 1
    fi
    rm soga.tar.gz -f
    
    if [[ ! -d ${temp_extract_dir}/soga ]]; then
        echo -e "${red}解压后未找到 soga 目录${plain}"
        rm -rf ${temp_extract_dir}
        exit 1
    fi
    
    # 备份旧版本（如果存在）
    if [[ -d /usr/local/soga ]]; then
        echo -e "${yellow}备份旧版本...${plain}"
        mv /usr/local/soga /usr/local/soga.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null
    fi
    
    # 移动到目标目录
    echo -e "${yellow}安装到: /usr/local/soga${plain}"
    mv ${temp_extract_dir}/soga /usr/local/soga
    if [[ $? -ne 0 ]]; then
        echo -e "${red}移动目录失败${plain}"
        rm -rf ${temp_extract_dir}
        exit 1
    fi
    
    rm -rf ${temp_extract_dir}
    
    # 验证安装
    if [[ ! -f /usr/local/soga/soga ]]; then
        echo -e "${red}错误: soga 二进制文件不存在${plain}"
        exit 1
    fi
    
    chmod +x /usr/local/soga/soga
    local version=$(/usr/local/soga/soga -v 2>/dev/null || echo "unknown")
    
    echo -e "${green}✓ soga 主程序安装成功${plain}"
    echo -e "${green}  版本: ${version}${plain}"
    echo -e "${green}  路径: /usr/local/soga/soga${plain}"
    echo ""
}

# 安装 soga 实例（创建配置目录和服务文件）
install_soga_instance() {
    local instance_num=$1
    local instance_name="soga${instance_num}"
    local config_dir="/etc/${instance_name}"
    
    # 如果是第一个实例，使用默认名称 soga
    if [[ $instance_num -eq 1 ]] && [[ ! -d /etc/soga ]]; then
        instance_name="soga"
        config_dir="/etc/soga"
    fi
    
    echo -e "${blue}========================================${plain}"
    echo -e "${green}安装 ${instance_name} 实例${plain}"
    echo -e "${blue}========================================${plain}"
    echo -e "${yellow}实例名称: ${instance_name}${plain}"
    echo -e "${yellow}配置目录: ${config_dir}${plain}"
    echo -e "${yellow}配置文件: ${config_dir}/soga.conf${plain}"
    echo ""
    
    # 检查其他已安装的实例（只检查配置目录）
    echo -e "${yellow}检查已安装的实例...${plain}"
    local other_instances=()
    for i in soga soga2 soga3 soga4; do
        if [[ "$i" != "$instance_name" ]]; then
            local other_config="/etc/${i}"
            if [[ "$i" == "soga" ]]; then
                other_config="/etc/soga"
            fi
            
            if [[ -d "$other_config" ]] && [[ -f "$other_config/soga.conf" ]]; then
                other_instances+=("$i")
                local run_mode=""
                if screen -list 2>/dev/null | grep -q "${i}"; then
                    run_mode="(screen)"
                elif systemctl is-active --quiet ${i} 2>/dev/null; then
                    run_mode="(systemd)"
                fi
                echo -e "  ${green}✓${plain} ${i} 已安装 ${run_mode}"
            fi
        fi
    done
    
    if [[ ${#other_instances[@]} -gt 0 ]]; then
        echo -e "${green}检测到 ${#other_instances[@]} 个已安装的实例，不会影响${plain}"
    fi
    echo ""
    
    # 检查 soga 主程序是否存在
    if [[ ! -f /usr/local/soga/soga ]]; then
        echo -e "${yellow}soga 主程序不存在，先安装主程序...${plain}"
        install_soga_binary
    fi
    
    # 检查并安装 screen
    if ! check_and_install_screen; then
        echo -e "${red}screen 安装失败，无法继续${plain}"
        wait_for_enter
        return 1
    fi
    
    # 检查实例是否已存在（只检查配置目录，不检查 systemd）
    if [[ -d "$config_dir" ]] && [[ -f "$config_dir/soga.conf" ]]; then
        echo -e "${yellow}${instance_name} 实例已存在（配置目录: ${config_dir}）${plain}"
        read -p "是否要重新安装? (y/n, 默认: n): " reinstall
        reinstall=${reinstall:-n}
        if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
            echo -e "${yellow}已取消${plain}"
            return 0
        fi
        
        # 只停止 screen 方式运行的实例（不处理 systemd）
        if screen -list 2>/dev/null | grep -q "${instance_name}"; then
            echo -e "${yellow}停止运行中的 ${instance_name} (screen 方式)...${plain}"
            screen -S ${instance_name} -X quit 2>/dev/null
            sleep 1
        fi
    fi
    
    # 创建配置目录
    mkdir -p ${config_dir} || {
        echo -e "${red}无法创建配置目录 ${config_dir}${plain}"
        exit 1
    }
    
    # 复制默认配置文件（如果不存在）
    if [[ ! -f ${config_dir}/soga.conf ]]; then
        if [[ -f /usr/local/soga/soga.conf ]]; then
            cp /usr/local/soga/soga.conf ${config_dir}/soga.conf
        else
            # 创建空配置文件
            touch ${config_dir}/soga.conf
        fi
        echo -e "${green}配置文件已创建: ${config_dir}/soga.conf${plain}"
    fi
    
    # 复制其他配置文件模板（如果存在）
    for file in blockList whiteList dns.yml routes.toml; do
        if [[ -f /usr/local/soga/${file} ]] && [[ ! -f ${config_dir}/${file} ]]; then
            cp /usr/local/soga/${file} ${config_dir}/${file} 2>/dev/null
        fi
    done
    
    echo -e "${green}✓ ${instance_name} 实例安装完成${plain}"
    echo -e "${green}  配置目录: ${config_dir}${plain}"
    echo -e "${green}  配置文件: ${config_dir}/soga.conf${plain}"
    echo ""
    
    # 检查配置文件是否有内容
    local has_config=0
    if [[ -f ${config_dir}/soga.conf ]] && [[ -s ${config_dir}/soga.conf ]]; then
        # 检查是否有基本配置
        if grep -qE "^(type|soga_key|webapi)" ${config_dir}/soga.conf 2>/dev/null; then
            has_config=1
        fi
    fi
    
    if [[ $has_config -eq 1 ]]; then
        echo -e "${yellow}检测到配置文件已有内容，是否现在启动 ${instance_name}? (y/n, 默认: y):${plain}"
        read -p "" start_now
        start_now=${start_now:-y}
        
        if [[ "$start_now" == "y" || "$start_now" == "Y" ]]; then
            echo ""
            start_instance ${instance_name}
        else
            echo -e "${yellow}安装完成，请稍后手动启动 ${instance_name}${plain}"
            echo -e "${yellow}启动命令: 使用脚本菜单选项 8-11${plain}"
            wait_for_enter
        fi
    else
        echo -e "${yellow}请先配置 ${instance_name}，然后启动实例${plain}"
        echo -e "${yellow}配置命令: 使用脚本菜单选项 5-7${plain}"
        echo -e "${yellow}启动命令: 使用脚本菜单选项 8-11${plain}"
        echo ""
        wait_for_enter
    fi
}

# 等待回车
wait_for_enter() {
    echo ""
    echo -n -e "${yellow}按回车返回主菜单: ${plain}"
    read temp
}

# 配置实例（使用默认配置）
config_instance_default() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    echo -e "${blue}开始配置 ${instance_name} 默认配置...${plain}"
    echo ""
    
    # 根据实例选择默认配置
    local default_type=""
    local default_server_type=""
    local default_soga_key=""
    local default_webapi_url=""
    local default_webapi_key=""
    
    if [[ "$instance_name" == "soga" ]]; then
        default_type=${SOGA_DEFAULT_TYPE}
        default_server_type=${SOGA_DEFAULT_SERVER_TYPE}
        default_soga_key=${SOGA_DEFAULT_SOGA_KEY}
        default_webapi_url=${SOGA_DEFAULT_WEBAPI_URL}
        default_webapi_key=${SOGA_DEFAULT_WEBAPI_KEY}
    elif [[ "$instance_name" == "soga2" ]]; then
        default_type=${SOGA2_DEFAULT_TYPE}
        default_server_type=${SOGA2_DEFAULT_SERVER_TYPE}
        default_soga_key=${SOGA2_DEFAULT_SOGA_KEY}
        default_webapi_url=${SOGA2_DEFAULT_WEBAPI_URL}
        default_webapi_key=${SOGA2_DEFAULT_WEBAPI_KEY}
    else
        echo -e "${red}该实例没有预设的默认配置，请使用自定义配置${plain}"
        wait_for_enter
        return 1
    fi
    
    # 检查配置是否完整
    if [[ -z "$default_soga_key" ]] || [[ -z "$default_webapi_url" ]] || [[ -z "$default_webapi_key" ]]; then
        echo -e "${red}错误: ${instance_name} 的默认配置未完整设置${plain}"
        wait_for_enter
        return 1
    fi
    
    # 让用户输入 node_id
    echo -e "${yellow}请输入 node_id (可以是数字或变量，如: 1 或 \$node_id):${plain}"
    read -r -p "node_id: " input_node_id
    
    if [[ -z "$input_node_id" ]]; then
        echo -e "${red}node_id 不能为空！${plain}"
        wait_for_enter
        return 1
    fi
    
    # 构建配置字符串
    local default_config="type=${default_type} server_type=${default_server_type} node_id=${input_node_id} soga_key=${default_soga_key} webapi_url=${default_webapi_url} webapi_key=${default_webapi_key}"
    
    echo ""
    echo -e "${yellow}配置参数: ${default_config}${plain}"
    read -p "确认使用以上配置? (y/n, 默认: y): " confirm
    confirm=${confirm:-y}
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${yellow}已取消配置${plain}"
        wait_for_enter
        return 0
    fi
    
    # 使用 soga 管理脚本的 config 命令
    echo -e "${yellow}正在配置...${plain}"
    /usr/local/soga/soga -c ${config_dir}/soga.conf config ${default_config} 2>&1
    
    # 或者直接使用管理脚本（如果存在）
    if [[ -f /usr/bin/${instance_name} ]]; then
        ${instance_name} config ${default_config} 2>&1
    else
        # 手动写入配置文件
        apply_config_to_file ${config_dir}/soga.conf ${default_config}
    fi
    
    echo ""
    echo -e "${green}${instance_name} 默认配置完成！${plain}"
    echo -e "${green}配置文件位置: ${config_dir}/soga.conf${plain}"
    
    # 重启实例
    echo ""
    echo -e "${yellow}是否现在启动 ${instance_name}? (y/n, 默认: y):${plain}"
    read -p "" start_now
    start_now=${start_now:-y}
    
    if [[ "$start_now" == "y" || "$start_now" == "Y" ]]; then
        # 如果已在运行，先停止
        if is_instance_running ${instance_name}; then
            stop_instance ${instance_name}
            sleep 1
        fi
        start_instance ${instance_name}
    else
        echo -e "${yellow}配置完成，请稍后手动启动 ${instance_name}${plain}"
        wait_for_enter
    fi
}

# 应用配置到文件
apply_config_to_file() {
    local config_file=$1
    shift
    local config_params="$@"
    
    for param in $config_params; do
        if [[ "$param" == *"="* ]]; then
            local key="${param%%=*}"
            local value="${param#*=}"
            
            # 更新或添加配置项
            if grep -q "^${key}=" "$config_file" 2>/dev/null; then
                sed -i "s|^${key}=.*|${key}=${value}|g" "$config_file"
            else
                echo "${key}=${value}" >> "$config_file"
            fi
        fi
    done
    
    # 确保 api=webapi（如果有 webapi 相关配置）
    if echo "$config_params" | grep -q "webapi"; then
        if ! grep -q "^api=" "$config_file" 2>/dev/null; then
            echo "api=webapi" >> "$config_file"
        elif ! grep -q "^api=webapi" "$config_file" 2>/dev/null; then
            sed -i "s|^api=.*|api=webapi|g" "$config_file"
        fi
    fi
}

# 配置实例（自定义配置）
config_instance_custom() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    echo -e "${blue}开始配置 ${instance_name} 自定义配置...${plain}"
    echo -e "${yellow}请输入配置参数${plain}"
    echo ""
    
    read -p "请输入 type (默认: xboard): " input_type
    input_type=${input_type:-xboard}
    
    read -p "请输入 server_type (默认: ss): " input_server_type
    input_server_type=${input_server_type:-ss}
    
    read -r -p "请输入 node_id (默认: \$node_id): " input_node_id
    input_node_id=${input_node_id:-'$node_id'}
    
    read -p "请输入 soga_key: " input_soga_key
    if [[ -z "$input_soga_key" ]]; then
        echo -e "${red}soga_key 不能为空！${plain}"
        wait_for_enter
        return 1
    fi
    
    read -p "请输入 webapi_url (默认: https://vowa.top/): " input_webapi_url
    input_webapi_url=${input_webapi_url:-https://vowa.top/}
    
    read -p "请输入 webapi_key: " input_webapi_key
    if [[ -z "$input_webapi_key" ]]; then
        echo -e "${red}webapi_key 不能为空！${plain}"
        wait_for_enter
        return 1
    fi
    
    # 构建配置字符串
    local custom_config="type=${input_type} server_type=${input_server_type} node_id=${input_node_id} soga_key=${input_soga_key} webapi_url=${input_webapi_url} webapi_key=${input_webapi_key}"
    
    echo ""
    echo -e "${yellow}配置参数: ${custom_config}${plain}"
    read -p "确认使用以上配置? (y/n, 默认: y): " confirm
    confirm=${confirm:-y}
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${yellow}已取消配置${plain}"
        wait_for_enter
        return 0
    fi
    
    # 应用配置
    echo -e "${yellow}正在配置...${plain}"
    apply_config_to_file ${config_dir}/soga.conf ${custom_config}
    
    echo ""
    echo -e "${green}${instance_name} 自定义配置完成！${plain}"
    echo -e "${green}配置文件位置: ${config_dir}/soga.conf${plain}"
    
    # 重启实例
    echo ""
    echo -e "${yellow}是否现在启动 ${instance_name}? (y/n, 默认: y):${plain}"
    read -p "" start_now
    start_now=${start_now:-y}
    
    if [[ "$start_now" == "y" || "$start_now" == "Y" ]]; then
        # 如果已在运行，先停止
        if is_instance_running ${instance_name}; then
            stop_instance ${instance_name}
            sleep 1
        fi
        start_instance ${instance_name}
    else
        echo -e "${yellow}配置完成，请稍后手动启动 ${instance_name}${plain}"
        wait_for_enter
    fi
}

# 启动实例（使用 screen）
start_instance() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    if is_instance_running ${instance_name}; then
        echo -e "${yellow}${instance_name} 已在运行中${plain}"
        wait_for_enter
        return 0
    fi
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    # 检查配置文件是否存在
    if [[ ! -f ${config_dir}/soga.conf ]]; then
        echo -e "${red}配置文件不存在: ${config_dir}/soga.conf${plain}"
        echo -e "${yellow}请先配置 ${instance_name}${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${yellow}正在启动 ${instance_name}...${plain}"
    echo -e "${yellow}配置文件: ${config_dir}/soga.conf${plain}"
    
    # 在 screen 中启动 soga
    screen -dmS ${instance_name} /usr/local/soga/soga -c ${config_dir}/soga.conf
    
    sleep 2
    
    if is_instance_running ${instance_name}; then
        echo -e "${green}${instance_name} 启动成功！${plain}"
        echo -e "${yellow}使用 'screen -r ${instance_name}' 查看日志${plain}"
    else
        echo -e "${red}${instance_name} 启动失败，请检查配置${plain}"
    fi
    
    wait_for_enter
}

# 停止实例
stop_instance() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    if ! is_instance_running ${instance_name}; then
        echo -e "${yellow}${instance_name} 未运行${plain}"
        wait_for_enter
        return 0
    fi
    
    echo -e "${yellow}正在停止 ${instance_name}...${plain}"
    
    # 优先停止 systemd 服务（旧脚本方式）
    if is_instance_using_systemd ${instance_name}; then
        if systemctl is-active --quiet ${instance_name} 2>/dev/null; then
            echo -e "${yellow}检测到 ${instance_name} 使用 systemd 运行，正在停止...${plain}"
            systemctl stop ${instance_name} 2>/dev/null
            sleep 2
        fi
    fi
    
    # 停止 screen 窗口（新脚本方式）
    if screen -list 2>/dev/null | grep -q "${instance_name}"; then
        echo -e "${yellow}检测到 ${instance_name} 使用 screen 运行，正在停止...${plain}"
        screen -S ${instance_name} -X quit 2>/dev/null
        sleep 2
        
        if screen -list 2>/dev/null | grep -q "${instance_name}"; then
            echo -e "${yellow}强制停止 screen 窗口...${plain}"
            screen -S ${instance_name} -X kill 2>/dev/null
            sleep 1
        fi
    fi
    
    if ! is_instance_running ${instance_name}; then
        echo -e "${green}${instance_name} 已停止${plain}"
    else
        echo -e "${yellow}${instance_name} 可能仍在运行${plain}"
    fi
    
    wait_for_enter
}

# 重启实例
restart_instance() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${yellow}正在重启 ${instance_name}...${plain}"
    
    # 先停止
    if is_instance_running ${instance_name}; then
        stop_instance ${instance_name}
        sleep 1
    fi
    
    # 再启动
    start_instance ${instance_name}
}

# 进入 screen 查看日志
enter_screen() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    # 检查并安装 screen
    if ! check_and_install_screen; then
        wait_for_enter
        return 1
    fi
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    echo -e "${blue}========================================${plain}"
    echo -e "${green}进入 ${instance_name} 的 screen 窗口${plain}"
    echo -e "${blue}========================================${plain}"
    echo ""
    echo -e "${yellow}screen 使用说明:${plain}"
    echo -e "  ${green}Ctrl+A${plain}，然后全松开，再按 ${green}D${plain}  - 离开当前 screen 窗口（不关闭）"
    echo -e "  ${green}Ctrl+A${plain}，然后全松开，再按 ${green}Esc${plain} - 进入复制模式（可用滚轮查看日志）"
    echo -e "  输入 ${green}exit${plain} - 退出并关闭当前 screen 窗口"
    echo ""
    echo -e "${yellow}按回车进入 screen...${plain}"
    read temp
    
    # 进入或创建 screen 窗口
    screen -R ${instance_name}
}

# 查看日志
view_log() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    echo -e "${blue}========================================${plain}"
    echo -e "${green}查看 ${instance_name} 日志${plain}"
    echo -e "${blue}========================================${plain}"
    echo ""
    echo -e "${yellow}日志文件位置: ${config_dir}/*.log${plain}"
    
    # 显示配置目录中的日志文件
    local log_files=$(ls -t ${config_dir}/*.log 2>/dev/null | head -5)
    if [[ -n "$log_files" ]]; then
        echo -e "${green}找到的日志文件:${plain}"
        echo "$log_files" | while read log_file; do
            if [[ -f "$log_file" ]]; then
                local file_size=$(du -h "$log_file" | cut -f1)
                echo -e "  ${green}✓${plain} $(basename $log_file) (${file_size})"
            fi
        done
        echo ""
    fi
    
    echo -e "${yellow}查看方式:${plain}"
    echo -e "  1. 进入 screen 窗口查看（推荐，实时日志）"
    echo -e "  2. 查看最新的日志文件内容"
    echo ""
    read -p "请选择 [1/2，默认1]: " log_choice
    log_choice=${log_choice:-1}
    
    if [[ "$log_choice" == "2" ]]; then
        local latest_log=$(ls -t ${config_dir}/*.log 2>/dev/null | head -1)
        if [[ -n "$latest_log" && -f "$latest_log" ]]; then
            echo ""
            echo -e "${blue}查看日志文件: ${latest_log}${plain}"
            echo -e "${yellow}（显示最后 100 行，按 q 退出）${plain}"
            echo ""
            tail -n 100 "$latest_log" | less -R
        else
            echo -e "${yellow}未找到日志文件${plain}"
            echo -e "${yellow}请使用 screen 方式查看实时日志${plain}"
        fi
    else
        enter_screen ${instance_name}
    fi
    
    wait_for_enter
}

# 卸载实例
uninstall_instance() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${yellow}确定要卸载 ${instance_name} 吗?${plain}"
    read -p "请输入 y 或 n (默认: n): " confirm
    confirm=${confirm:-n}
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${yellow}已取消卸载${plain}"
        wait_for_enter
        return 0
    fi
    
    echo -e "${yellow}正在卸载 ${instance_name}...${plain}"
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    # 停止运行中的实例
    if is_instance_running ${instance_name}; then
        stop_instance ${instance_name}
    fi
    
    # 删除配置目录
    if [[ -d "$config_dir" ]]; then
        echo -e "${yellow}删除配置目录: ${config_dir}${plain}"
        rm -rf "$config_dir"
    fi
    
    # 删除管理脚本（如果存在）
    if [[ -f "/usr/bin/${instance_name}" ]]; then
        rm -f "/usr/bin/${instance_name}"
    fi
    
    echo -e "${green}${instance_name} 卸载完成！${plain}"
    echo -e "${yellow}注意: soga 主程序 (/usr/local/soga) 未删除，其他实例仍可使用${plain}"
    echo -e "${yellow}注意: screen 窗口已关闭${plain}"
    
    wait_for_enter
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${blue}========================================${plain}"
    echo -e "${green}        soga 多实例管理脚本${plain}"
    echo -e "${blue}========================================${plain}"
    echo ""
    echo -e "${green}【主程序管理】${plain}"
    echo -e "  ${green}0.${plain} 安装/更新 soga 主程序（所有实例共享）"
    echo ""
    echo -e "${green}【安装选项】${plain}"
    echo -e "  ${green}1.${plain} 安装 soga 实例"
    echo -e "  ${green}2.${plain} 安装 soga2 实例"
    echo -e "  ${green}3.${plain} 安装 soga3 实例"
    echo -e "  ${green}4.${plain} 安装 soga4 实例"
    echo ""
    echo -e "${green}【配置选项】${plain}"
    echo -e "  ${green}5.${plain} 配置默认 soga 配置"
    echo -e "  ${green}6.${plain} 配置默认 soga2 配置"
    echo -e "  ${green}7.${plain} 自定义配置"
    echo ""
    echo -e "${green}【启动选项】${plain}"
    echo -e "  ${green}8.${plain} 启动 soga"
    echo -e "  ${green}9.${plain} 启动 soga2"
    echo -e "  ${green}10.${plain} 启动 soga3"
    echo -e "  ${green}11.${plain} 启动 soga4"
    echo ""
    echo -e "${green}【停止选项】${plain}"
    echo -e "  ${green}25.${plain} 停止 soga"
    echo -e "  ${green}26.${plain} 停止 soga2"
    echo -e "  ${green}27.${plain} 停止 soga3"
    echo -e "  ${green}28.${plain} 停止 soga4"
    echo ""
    echo -e "${green}【重启选项】${plain}"
    echo -e "  ${green}29.${plain} 重启 soga"
    echo -e "  ${green}30.${plain} 重启 soga2"
    echo -e "  ${green}31.${plain} 重启 soga3"
    echo -e "  ${green}32.${plain} 重启 soga4"
    echo ""
    echo -e "${green}【日志选项】${plain}"
    echo -e "  ${green}12.${plain} 查看 soga 日志"
    echo -e "  ${green}13.${plain} 查看 soga2 日志"
    echo -e "  ${green}14.${plain} 查看 soga3 日志"
    echo -e "  ${green}15.${plain} 查看 soga4 日志"
    echo ""
    echo -e "${green}【Screen 选项】${plain}"
    echo -e "  ${green}20.${plain} 进入 soga screen 窗口（查看日志）"
    echo -e "  ${green}21.${plain} 进入 soga2 screen 窗口（查看日志）"
    echo -e "  ${green}22.${plain} 进入 soga3 screen 窗口（查看日志）"
    echo -e "  ${green}23.${plain} 进入 soga4 screen 窗口（查看日志）"
    echo -e "  ${green}24.${plain} 查看所有 screen 窗口"
    echo ""
    echo -e "${green}【卸载选项】${plain}"
    echo -e "  ${green}16.${plain} 卸载 soga"
    echo -e "  ${green}17.${plain} 卸载 soga2"
    echo -e "  ${green}18.${plain} 卸载 soga3"
    echo -e "  ${green}19.${plain} 卸载 soga4"
    echo ""
    echo -e "  ${green}99.${plain} 退出脚本"
    echo ""
    echo -e "${blue}========================================${plain}"
    echo ""
    echo -e "${yellow}提示: soga 使用 screen 在后台运行${plain}"
    echo -e "${yellow}      使用 'screen -r ${instance_name}' 查看日志${plain}"
    echo ""
}

# 主逻辑
main() {
    is_cmd_exist "systemctl"
    if [[ $? != 0 ]]; then
        echo "systemctl 命令不存在，请使用较新版本的系统，例如 Ubuntu 18+、Debian 9+"
        exit 1
    fi
    
    while true; do
        show_main_menu
        read -p "请选择 [0-32, 99]: " choice
        
        case "${choice}" in
        0)
            install_soga_binary
            wait_for_enter
            ;;
        1)
            install_soga_instance 1
            ;;
        2)
            install_soga_instance 2
            ;;
        3)
            install_soga_instance 3
            ;;
        4)
            install_soga_instance 4
            ;;
        5)
            config_instance_default "soga"
            ;;
        6)
            config_instance_default "soga2"
            ;;
        7)
            echo ""
            echo -e "${yellow}请选择要配置的实例:${plain}"
            echo "1. soga"
            echo "2. soga2"
            echo "3. soga3"
            echo "4. soga4"
            read -p "请输入选择 [1-4]: " instance_choice
            case "${instance_choice}" in
            1) config_instance_custom "soga" ;;
            2) config_instance_custom "soga2" ;;
            3) config_instance_custom "soga3" ;;
            4) config_instance_custom "soga4" ;;
            *)
                echo -e "${red}无效选择${plain}"
                wait_for_enter
                ;;
            esac
            ;;
        8)
            start_instance "soga"
            ;;
        9)
            start_instance "soga2"
            ;;
        10)
            start_instance "soga3"
            ;;
        11)
            start_instance "soga4"
            ;;
        25)
            stop_instance "soga"
            ;;
        26)
            stop_instance "soga2"
            ;;
        27)
            stop_instance "soga3"
            ;;
        28)
            stop_instance "soga4"
            ;;
        29)
            restart_instance "soga"
            ;;
        30)
            restart_instance "soga2"
            ;;
        31)
            restart_instance "soga3"
            ;;
        32)
            restart_instance "soga4"
            ;;
        12)
            view_log "soga"
            ;;
        13)
            view_log "soga2"
            ;;
        14)
            view_log "soga3"
            ;;
        15)
            view_log "soga4"
            ;;
        16)
            uninstall_instance "soga"
            ;;
        17)
            uninstall_instance "soga2"
            ;;
        18)
            uninstall_instance "soga3"
            ;;
        19)
            uninstall_instance "soga4"
            ;;
        20)
            enter_screen "soga"
            ;;
        21)
            enter_screen "soga2"
            ;;
        22)
            enter_screen "soga3"
            ;;
        23)
            enter_screen "soga4"
            ;;
        24)
            if is_cmd_exist "screen"; then
                echo -e "${blue}所有 screen 窗口:${plain}"
                screen -ls
            else
                echo -e "${yellow}screen 未安装${plain}"
                check_and_install_screen
            fi
            wait_for_enter
            ;;
        99)
            echo -e "${green}退出脚本${plain}"
            exit 0
            ;;
        *)
            echo -e "${red}请输入正确的数字 [0-32, 99]${plain}"
            sleep 2
            ;;
        esac
    done
}

# 执行主函数
main $1
