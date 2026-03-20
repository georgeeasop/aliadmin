#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

# 流媒体路由配置
declare -A ROUTES_URLS=(
    ["asia"]="https://raw.githubusercontent.com/georgeeasop/aliadmin/refs/heads/main/ss/sg/routes.toml"
    ["kr"]="https://raw.githubusercontent.com/georgeeasop/aliadmin/refs/heads/main/ss/kr/routes.toml"
    ["jp"]="https://raw.githubusercontent.com/georgeeasop/aliadmin/refs/heads/main/ss/jp/routes.toml"
    ["us"]="https://raw.githubusercontent.com/georgeeasop/aliadmin/refs/heads/main/ss/us/routes.toml"
    ["tw"]="https://raw.githubusercontent.com/georgeeasop/aliadmin/refs/heads/main/ss/tw/routes.toml"
    ["eu"]="https://raw.githubusercontent.com/georgeeasop/aliadmin/refs/heads/main/ss/ou/routes.toml"
)

declare -A ROUTES_NAMES=(
    ["asia"]="亚洲"
    ["kr"]="韩国"
    ["jp"]="日本"
    ["us"]="美国"
    ["tw"]="台湾"
    ["eu"]="欧洲"
)

# 检查命令是否存在
is_cmd_exist() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查实例是否已安装
is_instance_installed() {
    local instance_name=$1
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    if [[ -d "$config_dir" ]] && [[ -f "$config_dir/soga.conf" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查实例是否在运行（检查 screen 窗口）
is_instance_running() {
    local instance_name=$1
    if screen -list 2>/dev/null | grep -q "${instance_name}"; then
        return 0
    else
        return 1
    fi
}

# 停止实例
stop_instance() {
    local instance_name=$1
    
    if ! is_instance_running ${instance_name}; then
        return 0
    fi
    
    echo -e "${yellow}正在停止 ${instance_name}...${plain}"
    
    # 发送 SIGTERM 信号到 screen 窗口中的进程
    screen -S ${instance_name} -X quit 2>/dev/null
    
    sleep 2
    
    if ! is_instance_running ${instance_name}; then
        return 0
    else
        # 尝试强制停止
        screen -S ${instance_name} -X kill 2>/dev/null
        sleep 1
        return 0
    fi
}

# 启动实例
start_instance() {
    local instance_name=$1
    local config_dir="/etc/${instance_name}"
    
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    # 检查配置文件是否存在
    if [[ ! -f ${config_dir}/soga.conf ]]; then
        echo -e "${red}配置文件不存在: ${config_dir}/soga.conf${plain}"
        return 1
    fi
    
    # 检查 soga 主程序是否存在
    if [[ ! -f /usr/local/soga/soga ]]; then
        echo -e "${red}soga 主程序不存在: /usr/local/soga/soga${plain}"
        return 1
    fi
    
    # 在 screen 中启动 soga
    screen -dmS ${instance_name} /usr/local/soga/soga -c ${config_dir}/soga.conf
    
    sleep 2
    
    if is_instance_running ${instance_name}; then
        return 0
    else
        return 1
    fi
}

# 安装流媒体路由
install_routes() {
    local route_type=$1
    local instance_name=$2
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装实例！${plain}"
        return 1
    fi
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    local route_url=${ROUTES_URLS[$route_type]}
    local route_name=${ROUTES_NAMES[$route_type]}
    local route_file="${config_dir}/routes.toml"
    
    if [[ -z "$route_url" ]]; then
        echo -e "${red}无效的流媒体类型: ${route_type}${plain}"
        return 1
    fi
    
    echo -e "${blue}========================================${plain}"
    echo -e "${green}安装流媒体路由${plain}"
    echo -e "${blue}========================================${plain}"
    echo -e "${yellow}流媒体类型: ${route_name}${plain}"
    echo -e "${yellow}实例名称: ${instance_name}${plain}"
    echo -e "${yellow}配置目录: ${config_dir}${plain}"
    echo -e "${yellow}路由文件: ${route_file}${plain}"
    echo -e "${yellow}下载地址: ${route_url}${plain}"
    echo ""
    
    # 检查 wget 是否存在
    if ! is_cmd_exist "wget"; then
        echo -e "${red}wget 命令不存在，正在安装...${plain}"
        if [[ -f /etc/redhat-release ]]; then
            yum install -y wget
        else
            apt-get update && apt-get install -y wget
        fi
    fi
    
    # 备份旧的路由文件
    if [[ -f "$route_file" ]]; then
        local backup_file="${route_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$route_file" "$backup_file"
        echo -e "${yellow}已备份旧文件: ${backup_file}${plain}"
    fi
    
    # 下载新的路由文件
    echo -e "${yellow}正在下载路由文件...${plain}"
    rm -f "$route_file"
    
    wget -qO "$route_file" "$route_url"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载失败！${plain}"
        # 恢复备份
        if [[ -f "$backup_file" ]]; then
            cp "$backup_file" "$route_file"
            echo -e "${yellow}已恢复备份文件${plain}"
        fi
        return 1
    fi
    
    # 验证文件是否下载成功
    if [[ ! -f "$route_file" ]] || [[ ! -s "$route_file" ]]; then
        echo -e "${red}下载的文件无效！${plain}"
        # 恢复备份
        if [[ -f "$backup_file" ]]; then
            cp "$backup_file" "$route_file"
            echo -e "${yellow}已恢复备份文件${plain}"
        fi
        return 1
    fi
    
    echo -e "${green}✓ 路由文件下载成功${plain}"
    echo -e "${green}  文件路径: ${route_file}${plain}"
    echo ""
    
    # 重启实例
    echo -e "${yellow}正在重启 ${instance_name}...${plain}"
    
    # 停止实例
    if is_instance_running ${instance_name}; then
        stop_instance ${instance_name}
        sleep 1
    fi
    
    # 启动实例
    if start_instance ${instance_name}; then
        echo -e "${green}✓ ${instance_name} 重启成功！${plain}"
        echo -e "${green}${route_name}流媒体已经更换成功${plain}"
        echo ""
        echo -e "${yellow}使用以下命令查看日志:${plain}"
        echo -e "${yellow}  screen -r ${instance_name}${plain}"
    else
        echo -e "${red}${instance_name} 重启失败，请检查配置${plain}"
        return 1
    fi
    
    return 0
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${blue}========================================${plain}"
    echo -e "${green}       soga 流媒体路由管理脚本${plain}"
    echo -e "${blue}========================================${plain}"
    echo ""
    echo -e "${green}【流媒体类型】${plain}"
    echo -e "  ${green}1.${plain} 亚洲 (asia)"
    echo -e "  ${green}2.${plain} 韩国 (kr)"
    echo -e "  ${green}3.${plain} 日本 (jp)"
    echo -e "  ${green}4.${plain} 美国 (us)"
    echo -e "  ${green}5.${plain} 台湾 (tw)"
    echo -e "  ${green}6.${plain} 欧洲 (eu)"
    echo ""
    echo -e "  ${green}0.${plain} 退出脚本"
    echo ""
    echo -e "${blue}========================================${plain}"
}

# 显示实例选择菜单
show_instance_menu() {
    echo ""
    echo -e "${green}【选择实例】${plain}"
    echo -e "  ${green}1.${plain} soga (soga1)"
    echo -e "  ${green}2.${plain} soga2"
    echo -e "  ${green}3.${plain} soga3"
    echo -e "  ${green}4.${plain} soga4"
    echo ""
    echo -e "  ${green}0.${plain} 返回"
    echo ""
}

# 主逻辑
main() {
    # 检查 root 权限
    [[ $EUID -ne 0 ]] && echo -e "${red}错误：必须使用root用户运行此脚本！\n" && exit 1
    
    # 检查 screen
    if ! is_cmd_exist "screen"; then
        echo -e "${yellow}screen 未安装，正在安装...${plain}"
        if [[ -f /etc/redhat-release ]]; then
            yum install -y screen
        else
            apt-get update && apt-get install -y screen
        fi
    fi
    
    while true; do
        show_main_menu
        read -p "请选择流媒体类型 [0-6]: " route_choice
        
        case "${route_choice}" in
        0)
            echo -e "${green}退出脚本${plain}"
            exit 0
            ;;
        1)
            route_type="asia"
            ;;
        2)
            route_type="kr"
            ;;
        3)
            route_type="jp"
            ;;
        4)
            route_type="us"
            ;;
        5)
            route_type="tw"
            ;;
        6)
            route_type="eu"
            ;;
        *)
            echo -e "${red}请输入正确的数字 [0-6]${plain}"
            sleep 2
            continue
            ;;
        esac
        
        # 显示实例选择菜单
        show_instance_menu
        read -p "请选择要安装的实例 [0-4]: " instance_choice
        
        case "${instance_choice}" in
        0)
            continue
            ;;
        1)
            instance_name="soga"
            ;;
        2)
            instance_name="soga2"
            ;;
        3)
            instance_name="soga3"
            ;;
        4)
            instance_name="soga4"
            ;;
        *)
            echo -e "${red}请输入正确的数字 [0-4]${plain}"
            sleep 2
            continue
            ;;
        esac
        
        # 安装流媒体路由
        install_routes "$route_type" "$instance_name"
        
        echo ""
        echo -n -e "${yellow}按回车继续: ${plain}"
        read temp
    done
}

# 执行主函数
main
