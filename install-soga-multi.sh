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
SOGA_DEFAULT_SOGA_KEY="5SrOk5VxovqomAVgKAIKBXGednyRpMSw"
SOGA_DEFAULT_WEBAPI_URL="https://vowa.top/"
SOGA_DEFAULT_WEBAPI_KEY="M2X84M6a7N0iGHWC8fU7p8bwrVcCBmz"

# soga2 默认配置（除 node_id 外，node_id 需要用户输入）
# 注意：soga2 的默认配置暂未提供，以下为占位符，可根据需要修改
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
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
  arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
  arch="arm64"
else
  arch="amd64"
  echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

function is_cmd_exist() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        return 1
    fi

    which "$cmd" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        return 0
    fi

    return 2
}

# 检测已安装的 soga 实例数量
detect_installed_instances() {
    local count=0
    
    # 检查 systemd 服务文件
    for service_file in /etc/systemd/system/soga*.service; do
        if [[ -f "$service_file" ]]; then
            # 排除 soga@.service（模板文件）
            if [[ "$service_file" != "/etc/systemd/system/soga@.service" ]]; then
                count=$((count + 1))
            fi
        fi
    done
    
    # 也检查 /usr/local/soga* 目录
    for soga_dir in /usr/local/soga*; do
        if [[ -d "$soga_dir" ]] && [[ -f "$soga_dir/soga" ]]; then
            count=$((count + 1))
        fi
    done
    
    # 去重：如果同时有服务和目录，只算一个
    # 简单处理：检查是否有 soga, soga1, soga2, soga3 等服务
    local unique_count=0
    for i in "" 1 2 3 4 5 6 7 8 9; do
        local service_name="soga${i}"
        if [[ -f "/etc/systemd/system/${service_name}.service" ]] || [[ -d "/usr/local/${service_name}" ]]; then
            unique_count=$((unique_count + 1))
        fi
    done
    
    echo $unique_count
}

# 获取下一个可用的实例编号
get_next_instance_number() {
    local installed_count=$(detect_installed_instances)
    
    if [[ $installed_count -eq 0 ]]; then
        echo "1"
    elif [[ $installed_count -eq 1 ]]; then
        # 检查是否有 soga（无编号）或 soga1
        if [[ -f "/etc/systemd/system/soga.service" ]] || [[ -d "/usr/local/soga" ]]; then
            echo "2"
        else
            echo "1"
        fi
    elif [[ $installed_count -eq 2 ]]; then
        echo "3"
    else
        echo $((installed_count + 1))
    fi
}

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl tar crontabs socat tzdata -y
    else
        apt install wget curl tar cron socat tzdata -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    local instance_name=$1
    if [[ ! -f /etc/systemd/system/${instance_name}.service ]]; then
        return 2
    fi
    temp=$(systemctl status ${instance_name} 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    if [[ ! -f /root/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh
        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    else
        echo -e "${yellow}acme.sh 已安装，跳过${plain}"
    fi
}

install_soga() {
    local instance_num=$1
    local instance_name="soga${instance_num}"
    local soga_dir="/usr/local/${instance_name}"
    local config_dir="/etc/${instance_name}"
    
    # 如果是第一个实例且没有安装过，使用默认名称 soga
    if [[ $instance_num -eq 1 ]] && [[ ! -f /etc/systemd/system/soga.service ]] && [[ ! -d /usr/local/soga ]]; then
        instance_name="soga"
        soga_dir="/usr/local/soga"
        config_dir="/etc/soga"
    fi
    
    echo -e "${blue}========================================${plain}"
    echo -e "${green}开始安装 ${instance_name}${plain}"
    echo -e "${blue}========================================${plain}"
    echo -e "${yellow}实例名称: ${instance_name}${plain}"
    echo -e "${yellow}程序目录: ${soga_dir}${plain}"
    echo -e "${yellow}配置目录: ${config_dir}${plain}"
    echo ""
    
    # 安全检查：列出所有已安装的实例，确保不会误操作
    echo -e "${yellow}已安装的实例检查:${plain}"
    local other_instances=()
    for i in soga soga1 soga2 soga3 soga4 soga5 soga6 soga7 soga8 soga9; do
        if [[ "$i" != "$instance_name" ]] && ([[ -f "/etc/systemd/system/${i}.service" ]] || [[ -d "/usr/local/${i}" ]]); then
            other_instances+=("$i")
            echo -e "  ${green}✓${plain} ${i} (已安装，不会被影响)"
        fi
    done
    echo ""
    
    cd /usr/local/ || {
        echo -e "${red}无法切换到 /usr/local/ 目录${plain}"
        exit 1
    }
    
    # 安全检查：只删除目标实例的目录，绝不删除其他实例
    if [[ -e ${soga_dir}/ ]]; then
        echo -e "${yellow}检测到已存在的目录 ${soga_dir}，将删除后重新安装${plain}"
        echo -e "${yellow}注意：只删除 ${instance_name} 的目录，不会影响其他实例${plain}"
        
        # 三重验证：确保目录路径正确
        local dir_name=$(basename "${soga_dir}")
        if [[ "$dir_name" == "$instance_name" ]] || [[ "$dir_name" == "soga" && "$instance_name" == "soga" ]]; then
            # 再次确认：检查是否与其他实例冲突
            local conflict=0
            for other in "${other_instances[@]}"; do
                if [[ "${soga_dir}" == "/usr/local/${other}" ]]; then
                    echo -e "${red}错误：目录与其他实例冲突！${plain}"
                    echo -e "${red}目录: ${soga_dir} 属于实例: ${other}${plain}"
                    conflict=1
                    break
                fi
            done
            
            if [[ $conflict -eq 0 ]]; then
                rm ${soga_dir}/ -rf
                echo -e "${green}已删除旧目录: ${soga_dir}${plain}"
            else
                exit 1
            fi
        else
            echo -e "${red}错误：目录路径不匹配，拒绝删除！${plain}"
            echo -e "${red}实例名称: ${instance_name}${plain}"
            echo -e "${red}目录名称: ${dir_name}${plain}"
            echo -e "${red}预期目录: /usr/local/${instance_name} 或 /usr/local/soga${plain}"
            echo -e "${red}实际目录: ${soga_dir}${plain}"
            exit 1
        fi
    fi

    if [[ $# -le 1 ]] || [[ -z "$2" ]]; then
        echo -e "开始安装 ${instance_name} 最新版"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz https://github.com/vaxilu/soga/releases/latest/download/soga-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 soga 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$2
        url="https://github.com/vaxilu/soga/releases/download/${last_version}/soga-linux-${arch}.tar.gz"
        echo -e "开始安装 ${instance_name} v$2"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 soga v$2 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    tar zxvf soga.tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}解压 soga 失败${plain}"
        exit 1
    fi
    rm soga.tar.gz -f
    if [[ ! -d soga ]]; then
        echo -e "${red}解压后未找到 soga 目录${plain}"
        exit 1
    fi
    cd soga
    
    # 重命名目录
    cd .. || {
        echo -e "${red}无法返回上级目录${plain}"
        exit 1
    }
    if [[ ! -d soga ]]; then
        echo -e "${red}未找到 soga 目录${plain}"
        exit 1
    fi
    mv soga ${instance_name}
    if [[ ! -d ${instance_name} ]]; then
        echo -e "${red}重命名目录失败${plain}"
        exit 1
    fi
    cd ${instance_name} || {
        echo -e "${red}无法进入 ${instance_name} 目录${plain}"
        exit 1
    }
    
    if [[ ! -f soga ]]; then
        echo -e "${red}未找到 soga 二进制文件${plain}"
        exit 1
    fi
    chmod +x soga
    last_version="$(./soga -v 2>/dev/null)"
    if [[ -z "$last_version" ]]; then
        echo -e "${yellow}警告: 无法获取 soga 版本信息${plain}"
        last_version="unknown"
    fi
    mkdir -p ${config_dir} || {
        echo -e "${red}无法创建配置目录 ${config_dir}${plain}"
        exit 1
    }
    
    # 修改服务文件中的路径 - 确保每个实例使用独立的路径
    if [[ -f soga.service ]]; then
        # 使用更精确的替换，避免误替换其他实例的路径
        sed -i "s|/usr/local/soga|${soga_dir}|g" soga.service
        sed -i "s|/etc/soga|${config_dir}|g" soga.service
        sed -i "s|Description=soga|Description=${instance_name}|g" soga.service
        sed -i "s|ExecStart=/usr/local/soga/soga|ExecStart=${soga_dir}/soga|g" soga.service
        
        # 确保 WorkingDirectory 指向配置目录，这样 soga 会从正确的目录读取配置
        if grep -q "WorkingDirectory=" soga.service; then
            sed -i "s|WorkingDirectory=.*|WorkingDirectory=${config_dir}|g" soga.service
        else
            # 如果没有 WorkingDirectory，在 [Service] 部分添加
            sed -i "/\[Service\]/a WorkingDirectory=${config_dir}" soga.service
        fi
        
        # 验证服务文件中的路径是否正确
        local service_exec=$(grep "ExecStart=" soga.service | cut -d'=' -f2 | cut -d' ' -f1)
        if [[ "$service_exec" != "${soga_dir}/soga" ]]; then
            echo -e "${red}错误: 服务文件路径修改失败！${plain}"
            echo -e "${red}预期: ${soga_dir}/soga${plain}"
            echo -e "${red}实际: ${service_exec}${plain}"
            exit 1
        fi
        
        # 验证 WorkingDirectory 是否正确
        local work_dir=$(grep "WorkingDirectory=" soga.service | cut -d'=' -f2)
        if [[ "$work_dir" != "${config_dir}" ]]; then
            echo -e "${yellow}警告: WorkingDirectory 可能不正确，将修复...${plain}"
            sed -i "s|WorkingDirectory=.*|WorkingDirectory=${config_dir}|g" soga.service
        fi
    fi
    
    if [[ -f soga@.service ]]; then
        sed -i "s|/usr/local/soga|${soga_dir}|g" soga@.service
        sed -i "s|/etc/soga|${config_dir}|g" soga@.service
    fi
    
    # 只删除目标实例的服务文件，不影响其他实例
    rm /etc/systemd/system/${instance_name}.service -f
    rm /etc/systemd/system/${instance_name}@.service -f 2>/dev/null
    
    if [[ -f soga.service ]]; then
        cp -f soga.service /etc/systemd/system/${instance_name}.service
        if [[ $? -ne 0 ]]; then
            echo -e "${red}复制服务文件失败${plain}"
            exit 1
        fi
        echo -e "${green}服务文件已创建: /etc/systemd/system/${instance_name}.service${plain}"
    else
        echo -e "${yellow}警告: 未找到 soga.service 文件${plain}"
    fi
    if [[ -f soga@.service ]]; then
        cp -f soga@.service /etc/systemd/system/${instance_name}@.service
    fi
    
    systemctl daemon-reload
    if [[ $? -ne 0 ]]; then
        echo -e "${yellow}警告: systemctl daemon-reload 失败${plain}"
    fi
    systemctl stop ${instance_name} 2>/dev/null
    systemctl enable ${instance_name}
    echo -e "${green}${instance_name} v${last_version}${plain} 安装完成，已设置开机自启"
    
    # 复制配置文件到实例专用的配置目录（确保每个实例独立）
    echo -e "${yellow}配置目录: ${config_dir}${plain}"
    if [[ ! -f ${config_dir}/soga.conf ]]; then
        cp soga.conf ${config_dir}/
        echo -e "${green}配置文件已复制到: ${config_dir}/soga.conf${plain}"
        echo -e ""
        echo -e "全新安装，请先配置必要的内容"
    else
        echo -e "${yellow}配置文件已存在: ${config_dir}/soga.conf${plain}"
        systemctl start ${instance_name}
        sleep 2
        check_status ${instance_name}
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}${instance_name} 重启成功${plain}"
        else
            echo -e "${red}${instance_name} 可能启动失败，请稍后使用 systemctl status ${instance_name} 查看状态${plain}"
        fi
    fi

    # 复制其他配置文件（每个实例独立）
    if [[ ! -f ${config_dir}/blockList ]]; then
        cp blockList ${config_dir}/ 2>/dev/null
    fi
    if [[ ! -f ${config_dir}/whiteList ]]; then
        cp whiteList ${config_dir}/ 2>/dev/null
    fi
    if [[ ! -f ${config_dir}/dns.yml ]]; then
        cp dns.yml ${config_dir}/ 2>/dev/null
    fi
    if [[ ! -f ${config_dir}/routes.toml ]]; then
        cp routes.toml ${config_dir}/ 2>/dev/null
    fi
    
    echo -e "${green}所有配置文件已复制到: ${config_dir}/${plain}"
    
    # 安装管理脚本
    # 如果是第一个实例且已存在原始 soga 命令，先备份
    if [[ $instance_num -eq 1 ]] && [[ "$instance_name" == "soga" ]] && [[ -f /usr/bin/soga ]]; then
        if grep -q "vaxilu/soga" /usr/bin/soga 2>/dev/null || grep -q "soga 管理脚本" /usr/bin/soga 2>/dev/null; then
            echo -e "${yellow}检测到已存在的 soga 管理命令，将替换为新版本${plain}"
            # 备份原命令（可选）
            # cp /usr/bin/soga /usr/bin/soga.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null
        fi
    fi
    install_management_script ${instance_name} ${soga_dir} ${config_dir}
    
    # 安装 soga-tool（如果不存在或需要更新）
    curl -o /usr/bin/${instance_name}-tool -Ls https://raw.githubusercontent.com/vaxilu/soga/master/soga-tool-${arch}
    if [[ $? -ne 0 ]]; then
        echo -e "${yellow}警告: 下载 ${instance_name}-tool 失败，但安装将继续${plain}"
    else
        chmod +x /usr/bin/${instance_name}-tool
    fi
    
    echo -e ""
    echo -e "${green}${instance_name} 安装完成！${plain}"
    echo -e "${blue}========================================${plain}"
    echo -e "${green}安装信息确认:${plain}"
    echo -e "  实例名称: ${instance_name}"
    echo -e "  程序目录: ${soga_dir}"
    echo -e "  配置目录: ${config_dir}"
    echo -e "  服务文件: /etc/systemd/system/${instance_name}.service"
    echo -e "  配置文件: ${config_dir}/soga.conf"
    echo -e "${blue}========================================${plain}"
    
    # 最终验证：确保所有路径都正确且独立
    local verify_ok=1
    if [[ ! -d "${soga_dir}" ]]; then
        echo -e "${red}✗ 验证失败: 程序目录不存在${plain}"
        verify_ok=0
    fi
    if [[ ! -f "${soga_dir}/soga" ]]; then
        echo -e "${red}✗ 验证失败: 可执行文件不存在${plain}"
        verify_ok=0
    fi
    if [[ ! -f "/etc/systemd/system/${instance_name}.service" ]]; then
        echo -e "${red}✗ 验证失败: 服务文件不存在${plain}"
        verify_ok=0
    fi
    if [[ ! -d "${config_dir}" ]]; then
        echo -e "${red}✗ 验证失败: 配置目录不存在${plain}"
        verify_ok=0
    fi
    
    if [[ $verify_ok -eq 1 ]]; then
        echo -e "${green}✓ 所有路径验证通过，实例 ${instance_name} 已独立安装${plain}"
    else
        echo -e "${red}✗ 验证失败，请检查安装过程${plain}"
    fi
}

# 生成多实例管理脚本
install_management_script() {
    local instance_name=$1
    local soga_dir=$2
    local config_dir=$3
    
    cat > /usr/bin/${instance_name} << 'SCRIPT_EOF'
#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 从命令名获取实例名称（须与 systemd 服务名一致：soga / soga2 / soga1 …）
INSTANCE_NAME=$(basename "$0")
SOGA_DIR="__SOGA_DIR__"
CONFIG_DIR="__CONFIG_DIR__"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

confirm() {
 if [[ $# > 1 ]]; then
 echo && read -p "$1 [默认$2]: " temp
 if [[ x"${temp}" == x"" ]]; then
 temp=$2
 fi
 else
 read -p "$1 [y/n]: " temp
 fi
 if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
 return 0
 else
 return 1
 fi
}

confirm_restart() {
 confirm "是否重启${INSTANCE_NAME}" "y"
 if [[ $? == 0 ]]; then
 restart
 else
 show_menu
 fi
}

before_show_menu() {
 echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
 show_menu
}

start() {
 check_status
 if [[ $? == 0 ]]; then
 echo ""
 echo -e "${green}${INSTANCE_NAME}已运行，无需再次启动，如需重启请选择重启${plain}"
 else
 systemctl reset-failed ${INSTANCE_NAME}
 systemctl start ${INSTANCE_NAME}
 sleep 2
 check_status
 if [[ $? == 0 ]]; then
 echo -e "${green}${INSTANCE_NAME} 启动成功，请使用 ${INSTANCE_NAME} log 查看运行日志${plain}"
 else
 echo -e "${red}${INSTANCE_NAME}可能启动失败，请稍后使用 ${INSTANCE_NAME} log 查看日志信息${plain}"
 fi
 fi

 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

stop() {
 systemctl stop ${INSTANCE_NAME}
 sleep 2
 check_status
 if [[ $? == 1 ]]; then
 echo -e "${green}${INSTANCE_NAME} 停止成功${plain}"
 else
 echo -e "${red}${INSTANCE_NAME}停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
 fi

 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

restart() {
 systemctl reset-failed ${INSTANCE_NAME}
 systemctl restart ${INSTANCE_NAME}
 sleep 2
 check_status
 if [[ $? == 0 ]]; then
 echo -e "${green}${INSTANCE_NAME} 重启成功，请使用 ${INSTANCE_NAME} log 查看运行日志${plain}"
 else
 echo -e "${red}${INSTANCE_NAME}可能启动失败，请稍后使用 ${INSTANCE_NAME} log 查看日志信息${plain}"
 fi
 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

enable() {
 systemctl enable ${INSTANCE_NAME}
 if [[ $? == 0 ]]; then
 echo -e "${green}${INSTANCE_NAME} 设置开机自启成功${plain}"
 else
 echo -e "${red}${INSTANCE_NAME} 设置开机自启失败${plain}"
 fi

 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

disable() {
 systemctl disable ${INSTANCE_NAME}
 if [[ $? == 0 ]]; then
 echo -e "${green}${INSTANCE_NAME} 取消开机自启成功${plain}"
 else
 echo -e "${red}${INSTANCE_NAME} 取消开机自启失败${plain}"
 fi

 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

show_log() {
 n="$2"
 if [[ $2 == "" ]]; then
 n="1000"
 fi
 journalctl -u ${INSTANCE_NAME}.service -e --no-pager -f -n "${n}"
 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

update() {
 if [[ $# == 0 ]]; then
 echo && echo -n -e "输入指定版本(默认最新版): " && read version
 else
 version=$2
 fi
 echo -e "${yellow}请使用 install-soga-multi.sh 脚本更新多实例${plain}"
 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

# 说明：官方 soga-tool 多数情况下固定写 /etc/soga/soga.conf，多实例会串配置。
# 此处改为只向「本实例」的 soga.conf 写入 key=value，互不干扰。
apply_kv_to_soga_conf() {
 local conf="$1"
 local tpl_dir="$2"
 shift 2
 mkdir -p "$(dirname "$conf")"
 if [[ ! -f "$conf" ]]; then
   if [[ -f "${tpl_dir}/soga.conf" ]]; then
     cp "${tpl_dir}/soga.conf" "$conf"
   else
     echo -e "${red}缺少模板: ${tpl_dir}/soga.conf${plain}"
     return 1
   fi
 fi
 local arg key val found tmp
 for arg in "$@"; do
   [[ "$arg" == *=* ]] || continue
   key="${arg%%=*}"
   val="${arg#*=}"
   [[ -n "$key" ]] || continue
   found=0
   tmp="${conf}.tmp.$$"
   while IFS= read -r line || [[ -n "$line" ]]; do
     if [[ "$line" == "${key}="* ]]; then
       printf '%s\n' "${key}=${val}"
       found=1
     else
       printf '%s\n' "$line"
     fi
   done < "$conf" > "$tmp" || return 1
   if [[ $found -eq 0 ]]; then
     printf '%s\n' "${key}=${val}" >> "$tmp"
   fi
   mv "$tmp" "$conf" || return 1
 done
 local need_api=0
 for arg in "$@"; do
   [[ "$arg" == webapi_url=* || "$arg" == webapi_key=* ]] && need_api=1
 done
 if [[ $need_api -eq 1 ]]; then
   found=0
   tmp="${conf}.tmp.$$"
   while IFS= read -r line || [[ -n "$line" ]]; do
     if [[ "$line" == "api="* ]]; then
       printf '%s\n' "api=webapi"
       found=1
     else
       printf '%s\n' "$line"
     fi
   done < "$conf" > "$tmp" || return 1
   if [[ $found -eq 0 ]]; then
     printf '%s\n' "api=webapi" >> "$tmp"
   fi
   mv "$tmp" "$conf" || return 1
 fi
 return 0
}

config() {
 # 配置目录严格基于命令名（服务名）：soga -> /etc/soga，soga2 -> /etc/soga2，soga1 -> /etc/soga1
 # 绝不使用 CONFIG_DIR 变量，避免混淆
 local current_config_dir="/etc/${INSTANCE_NAME}"
 local conf="${current_config_dir}/soga.conf"
 
 # 验证实例名称有效性（防止空值或错误值）
 if [[ -z "${INSTANCE_NAME}" ]] || [[ "${INSTANCE_NAME}" == "__INSTANCE_NAME__" ]]; then
   echo -e "${red}错误: 无法确定实例名称${plain}"
   return 1
 fi

 if [[ $# -gt 1 ]]; then
   shift
   if [[ ! -d "${SOGA_DIR}" ]]; then
     echo -e "${red}程序目录不存在: ${SOGA_DIR}${plain}"
     return 1
   fi
   
   # 明确显示正在配置哪个实例，防止混淆
   echo -e "${yellow}========================================${plain}"
   echo -e "${yellow}正在配置实例: ${INSTANCE_NAME}${plain}"
   echo -e "${yellow}配置文件: ${conf}${plain}"
   echo -e "${yellow}程序目录: ${SOGA_DIR}${plain}"
   echo -e "${yellow}========================================${plain}"
   echo ""
   
   # 验证：确保不会配置到错误的文件
   local expected_conf="/etc/${INSTANCE_NAME}/soga.conf"
   if [[ "$conf" != "$expected_conf" ]]; then
     echo -e "${red}错误: 配置路径不匹配！${plain}"
     echo -e "${red}预期: ${expected_conf}${plain}"
     echo -e "${red}实际: ${conf}${plain}"
     return 1
   fi
   
   apply_kv_to_soga_conf "$conf" "${SOGA_DIR}" "$@" || return 1
   echo ""
   echo -e "${green}配置完成！${plain}"
   echo -e "${green}配置文件: ${conf}${plain}"
   
   # 验证配置是否真的写入了正确的文件
   if [[ -f "$conf" ]]; then
     echo -e "${green}✓ 配置文件已更新${plain}"
   else
     echo -e "${red}✗ 警告: 配置文件可能未创建${plain}"
   fi
 else
   # 显示配置文件内容
   if [[ -f "$conf" ]]; then
     echo -e "${yellow}实例: ${INSTANCE_NAME}${plain}"
     echo -e "${yellow}配置文件位置: ${conf}${plain}"
     echo ""
     cat "$conf"
   else
     echo -e "${red}配置文件不存在: ${conf}${plain}"
     echo -e "${yellow}实例: ${INSTANCE_NAME}${plain}"
   fi
 fi
}

uninstall() {
 confirm "确定要卸载 ${INSTANCE_NAME} 吗?" "n"
 if [[ $? != 0 ]]; then
 if [[ $# == 0 ]]; then
 show_menu
 fi
 return 0
 fi
 systemctl stop ${INSTANCE_NAME}
 systemctl disable ${INSTANCE_NAME}
 rm /etc/systemd/system/${INSTANCE_NAME}.service -f
 systemctl daemon-reload
 systemctl reset-failed
 rm ${CONFIG_DIR}/ -rf
 rm ${SOGA_DIR}/ -rf
 rm /usr/bin/${INSTANCE_NAME} -f
 rm /usr/bin/${INSTANCE_NAME}-tool -f

 echo ""
 echo -e "卸载成功"
 echo ""

 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
 if [[ ! -f /etc/systemd/system/${INSTANCE_NAME}.service ]]; then
 return 2
 fi
 temp=$(systemctl status ${INSTANCE_NAME} 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
 if [[ x"${temp}" == x"running" ]]; then
 return 0
 else
 return 1
 fi
}

check_enabled() {
 temp=$(systemctl is-enabled ${INSTANCE_NAME} 2>/dev/null)
 if [[ x"${temp}" == x"enabled" ]]; then
 return 0
 else
 return 1;
 fi
}

check_install() {
 check_status
 if [[ $? == 2 ]]; then
 echo ""
 echo -e "${red}请先安装${INSTANCE_NAME}${plain}"
 if [[ $# == 0 ]]; then
 before_show_menu
 fi
 return 1
 else
 return 0
 fi
}

show_status() {
 check_status
 case $? in
 0)
 echo -e "${INSTANCE_NAME}状态: ${green}已运行${plain}"
 show_enable_status
 ;;
 1)
 echo -e "${INSTANCE_NAME}状态: ${yellow}未运行${plain}"
 show_enable_status
 ;;
 2)
 echo -e "${INSTANCE_NAME}状态: ${red}未安装${plain}"
 esac
}

show_enable_status() {
 check_enabled
 if [[ $? == 0 ]]; then
 echo -e "是否开机自启: ${green}是${plain}"
 else
 echo -e "是否开机自启: ${red}否${plain}"
 fi
}

show_soga_version() {
 echo -n "${INSTANCE_NAME} 版本："
 ${SOGA_DIR}/soga -v
 echo ""
 if [[ $# == 0 ]]; then
 before_show_menu
 fi
}

show_usage() {
 echo "${INSTANCE_NAME} 管理脚本使用方法: "
 echo "------------------------------------------"
 echo "${INSTANCE_NAME} - 显示管理菜单 (功能更多)"
 echo "${INSTANCE_NAME} start - 启动 ${INSTANCE_NAME}"
 echo "${INSTANCE_NAME} stop - 停止 ${INSTANCE_NAME}"
 echo "${INSTANCE_NAME} restart - 重启 ${INSTANCE_NAME}"
 echo "${INSTANCE_NAME} enable - 设置 ${INSTANCE_NAME} 开机自启"
 echo "${INSTANCE_NAME} disable - 取消 ${INSTANCE_NAME} 开机自启"
 echo "${INSTANCE_NAME} log - 查看 ${INSTANCE_NAME} 日志"
 echo "${INSTANCE_NAME} config - 显示配置文件内容"
 echo "${INSTANCE_NAME} config xx=xx yy=yy - 自动设置配置文件"
 echo "${INSTANCE_NAME} version - 查看 ${INSTANCE_NAME} 版本"
 echo "------------------------------------------"
}

show_menu() {
 echo -e "
 ${green}${INSTANCE_NAME} 后端管理脚本${plain}

 ${green}0.${plain} 退出脚本
————————————————
 ${green}4.${plain} 启动 ${INSTANCE_NAME}
 ${green}5.${plain} 停止 ${INSTANCE_NAME}
 ${green}6.${plain} 重启 ${INSTANCE_NAME}
 ${green}7.${plain} 查看 ${INSTANCE_NAME} 日志
————————————————
 ${green}8.${plain} 设置 ${INSTANCE_NAME} 开机自启
 ${green}9.${plain} 取消 ${INSTANCE_NAME} 开机自启
————————————————
 ${green}10.${plain} 查看 ${INSTANCE_NAME} 版本
 ${green}11.${plain} 配置 ${INSTANCE_NAME}
 ${green}12.${plain} 卸载 ${INSTANCE_NAME}
 "
 show_status
 echo && read -p "请输入选择 [0-12]: " num

 case "${num}" in
 0) exit 0
 ;;
 4) check_install && start
 ;;
 5) check_install && stop
 ;;
 6) check_install && restart
 ;;
 7) check_install && show_log
 ;;
 8) check_install && enable
 ;;
 9) check_install && disable
 ;;
 10) check_install && show_soga_version
 ;;
 11) check_install && config
 ;;
 12) check_install && uninstall
 ;;
 *) echo -e "${red}请输入正确的数字 [0-12]${plain}"
 ;;
 esac
}


if [[ $# > 0 ]]; then
 case $1 in
 "start") check_install 0 && start 0
 ;;
 "stop") check_install 0 && stop 0
 ;;
 "restart") check_install 0 && restart 0
 ;;
 "enable") check_install 0 && enable 0
 ;;
 "disable") check_install 0 && disable 0
 ;;
 "log") check_install 0 && show_log 0 $2
 ;;
 "config") config $*
 ;;
 "uninstall") check_install 0 && uninstall 0
 ;;
 "version") check_install 0 && show_soga_version 0
 ;;
 *) show_usage
 esac
else
 show_menu
fi
SCRIPT_EOF

    # 替换占位符
    sed -i "s|__SOGA_DIR__|${soga_dir}|g" /usr/bin/${instance_name}
    sed -i "s|__CONFIG_DIR__|${config_dir}|g" /usr/bin/${instance_name}
    chmod +x /usr/bin/${instance_name}
}

# 检查实例是否已安装
is_instance_installed() {
    local instance_name=$1
    if [[ -f /etc/systemd/system/${instance_name}.service ]] || [[ -d /usr/local/${instance_name} ]]; then
        return 0
    else
        return 1
    fi
}

# 配置 soga 实例（使用默认配置）
config_instance_default() {
    local instance_name=$1
    local instance_num=$2
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    # 配置目录与 systemd 服务名一致：soga->/etc/soga，soga2->/etc/soga2，soga1->/etc/soga1
    local config_dir="/etc/${instance_name}"
    if [[ ! -d "$config_dir" ]] && [[ -f /etc/systemd/system/${instance_name}.service ]]; then
        mkdir -p "$config_dir"
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
    if [[ "$instance_name" == "soga" ]]; then
        if [[ -z "$default_soga_key" ]] || [[ -z "$default_webapi_url" ]] || [[ -z "$default_webapi_key" ]]; then
            echo -e "${red}错误: soga 的默认配置未完整设置，请先编辑脚本顶部的默认配置参数${plain}"
            wait_for_enter
            return 1
        fi
    elif [[ "$instance_name" == "soga2" ]]; then
        if [[ -z "$default_soga_key" ]] || [[ -z "$default_webapi_url" ]] || [[ -z "$default_webapi_key" ]]; then
            echo -e "${yellow}警告: soga2 的默认配置未完整设置，请先编辑脚本顶部的默认配置参数${plain}"
            wait_for_enter
            return 1
        fi
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
    if [[ -f /usr/bin/${instance_name} ]]; then
        # 验证实例名称和配置目录的一致性
        local expected_config_dir="/etc/${instance_name}"
        if [[ "$config_dir" != "$expected_config_dir" ]]; then
            echo -e "${red}错误: 配置目录不匹配！${plain}"
            echo -e "${red}实例名称: ${instance_name}${plain}"
            echo -e "${red}预期目录: ${expected_config_dir}${plain}"
            echo -e "${red}实际目录: ${config_dir}${plain}"
            wait_for_enter
            return 1
        fi
        
        mkdir -p "${config_dir}" || {
            echo -e "${red}无法创建配置目录 ${config_dir}${plain}"
            wait_for_enter
            return 1
        }
        
        echo -e "${yellow}========================================${plain}"
        echo -e "${yellow}正在配置实例: ${instance_name}${plain}"
        echo -e "${yellow}配置目录: ${config_dir}${plain}"
        echo -e "${yellow}配置文件: ${config_dir}/soga.conf${plain}"
        echo -e "${yellow}========================================${plain}"
        echo ""
        echo -e "${yellow}执行命令: ${instance_name} config ${default_config}${plain}"
        echo ""
        
        ${instance_name} config ${default_config} 2>&1
        local config_result=$?
        echo ""
        
        # 检查配置是否成功
        sleep 1
        
        # 验证配置是否真的写入了正确的文件
        if [[ -f "${config_dir}/soga.conf" ]]; then
            # 检查配置文件内容
            if grep -q "type=" "${config_dir}/soga.conf" 2>/dev/null && grep -q "soga_key=" "${config_dir}/soga.conf" 2>/dev/null; then
                # 验证配置目录是否正确（防止配置到错误的目录）
                local actual_config=$(grep -E "^(type|soga_key|webapi_url)=" "${config_dir}/soga.conf" 2>/dev/null | head -3)
                echo -e "${green}${instance_name} 默认配置完成！${plain}"
                echo -e "${green}配置文件位置: ${config_dir}/soga.conf${plain}"
                echo -e "${green}配置内容预览:${plain}"
                echo "$actual_config" | head -3
                
                # 重启服务
                echo ""
                echo -e "${yellow}正在重启 ${instance_name}...${plain}"
                systemctl restart ${instance_name}
                sleep 2
                if systemctl is-active --quiet ${instance_name}; then
                    echo -e "${green}${instance_name} 重启成功！${plain}"
                else
                    echo -e "${red}${instance_name} 重启失败，请检查日志${plain}"
                fi
            else
                echo -e "${red}配置写入失败，配置文件内容未更新${plain}"
                echo -e "${yellow}配置文件位置: ${config_dir}/soga.conf${plain}"
                echo -e "${yellow}请检查配置文件内容${plain}"
            fi
        else
            echo -e "${red}配置文件未创建: ${config_dir}/soga.conf${plain}"
            echo -e "${yellow}请手动运行: ${instance_name} config ${default_config}${plain}"
        fi
    else
        echo -e "${red}${instance_name} 管理脚本不存在，请先安装 ${instance_name}${plain}"
    fi
    
    wait_for_enter
}

# 配置 soga 实例（自定义配置）
config_instance_custom() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${blue}开始配置 ${instance_name} 自定义配置...${plain}"
    echo -e "${yellow}请输入配置参数${plain}"
    echo -e "${yellow}注意: 如果 node_id 需要变量，请输入: \$node_id${plain}"
    echo ""
    
    # 提示输入各个参数
    read -p "请输入 type (默认: xboard): " input_type
    input_type=${input_type:-xboard}
    
    read -p "请输入 server_type (默认: ss): " input_server_type
    input_server_type=${input_server_type:-ss}
    
    read -r -p "请输入 node_id (默认: \$node_id，如需变量请直接输入 \$node_id): " input_node_id
    if [[ -z "$input_node_id" ]]; then
        input_node_id='$node_id'
    fi
    
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
    
    # 使用 soga 管理脚本的 config 命令
    if [[ -f /usr/bin/${instance_name} ]]; then
        local config_dir="/etc/${instance_name}"
        
        # 验证实例名称和配置目录的一致性
        local expected_config_dir="/etc/${instance_name}"
        if [[ "$config_dir" != "$expected_config_dir" ]]; then
            echo -e "${red}错误: 配置目录不匹配！${plain}"
            echo -e "${red}实例名称: ${instance_name}${plain}"
            echo -e "${red}预期目录: ${expected_config_dir}${plain}"
            echo -e "${red}实际目录: ${config_dir}${plain}"
            wait_for_enter
            return 1
        fi
        
        mkdir -p "${config_dir}" || {
            echo -e "${red}无法创建配置目录 ${config_dir}${plain}"
            wait_for_enter
            return 1
        }
        
        echo -e "${yellow}========================================${plain}"
        echo -e "${yellow}正在配置实例: ${instance_name}${plain}"
        echo -e "${yellow}配置目录: ${config_dir}${plain}"
        echo -e "${yellow}配置文件: ${config_dir}/soga.conf${plain}"
        echo -e "${yellow}========================================${plain}"
        echo ""
        echo -e "${yellow}执行命令: ${instance_name} config ${custom_config}${plain}"
        echo ""
        
        ${instance_name} config ${custom_config} 2>&1
        local config_result=$?
        echo ""
        
        # 检查配置是否成功
        sleep 1
        
        # 验证配置是否真的写入了正确的文件
        if [[ -f "${config_dir}/soga.conf" ]]; then
            # 检查配置文件内容
            if grep -q "type=" "${config_dir}/soga.conf" 2>/dev/null && grep -q "soga_key=" "${config_dir}/soga.conf" 2>/dev/null; then
                # 验证配置目录是否正确（防止配置到错误的目录）
                local actual_config=$(grep -E "^(type|soga_key|webapi_url)=" "${config_dir}/soga.conf" 2>/dev/null | head -3)
                echo -e "${green}${instance_name} 自定义配置完成！${plain}"
                echo -e "${green}配置文件位置: ${config_dir}/soga.conf${plain}"
                echo -e "${green}配置内容预览:${plain}"
                echo "$actual_config" | head -3
                
                # 重启服务
                echo ""
                echo -e "${yellow}正在重启 ${instance_name}...${plain}"
                systemctl restart ${instance_name}
                sleep 2
                if systemctl is-active --quiet ${instance_name}; then
                    echo -e "${green}${instance_name} 重启成功！${plain}"
                else
                    echo -e "${red}${instance_name} 重启失败，请检查日志${plain}"
                fi
            else
                echo -e "${red}配置写入失败，配置文件内容未更新${plain}"
                echo -e "${yellow}配置文件位置: ${config_dir}/soga.conf${plain}"
                echo -e "${yellow}请检查配置文件内容${plain}"
            fi
        else
            echo -e "${red}配置文件未创建: ${config_dir}/soga.conf${plain}"
            echo -e "${yellow}请手动运行: ${instance_name} config ${custom_config}${plain}"
        fi
    else
        echo -e "${red}${instance_name} 管理脚本不存在，请先安装 ${instance_name}${plain}"
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
    systemctl restart ${instance_name}
    sleep 2
    if systemctl is-active --quiet ${instance_name}; then
        echo -e "${green}${instance_name} 重启成功！${plain}"
    else
        echo -e "${red}${instance_name} 重启失败，请检查日志${plain}"
    fi
    
    wait_for_enter
}

# 查看日志
view_log() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装，请先安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${blue}查看 ${instance_name} 日志（按 Ctrl+C 退出）...${plain}"
    echo ""
    journalctl -u ${instance_name}.service -f --no-pager -n 100 || true
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
    systemctl stop ${instance_name} 2>/dev/null
    systemctl disable ${instance_name} 2>/dev/null
    rm /etc/systemd/system/${instance_name}.service -f
    rm /etc/systemd/system/${instance_name}@.service -f 2>/dev/null
    systemctl daemon-reload
    systemctl reset-failed
    
    local config_dir="/etc/${instance_name}"
    if [[ "$instance_name" == "soga" ]]; then
        config_dir="/etc/soga"
    fi
    
    rm ${config_dir}/ -rf
    rm /usr/local/${instance_name}/ -rf
    rm /usr/bin/${instance_name} -f 2>/dev/null
    rm /usr/bin/${instance_name}-tool -f 2>/dev/null
    
    echo -e "${green}${instance_name} 卸载完成！${plain}"
    wait_for_enter
}

# 检查实例文件完整性
check_instance_files() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${blue}检查 ${instance_name} 文件完整性...${plain}"
    echo ""
    
    # 确定正确的路径
    local soga_dir="/usr/local/${instance_name}"
    local config_dir="/etc/${instance_name}"
    
    if [[ "$instance_name" == "soga" ]]; then
        soga_dir="/usr/local/soga"
        config_dir="/etc/soga"
    fi
    
    local has_error=0
    
    # 检查程序目录
    if [[ ! -d "$soga_dir" ]]; then
        echo -e "${red}✗ 程序目录不存在: ${soga_dir}${plain}"
        has_error=1
    else
        echo -e "${green}✓ 程序目录存在: ${soga_dir}${plain}"
    fi
    
    # 检查可执行文件
    if [[ ! -f "${soga_dir}/soga" ]]; then
        echo -e "${red}✗ 可执行文件不存在: ${soga_dir}/soga${plain}"
        has_error=1
    else
        echo -e "${green}✓ 可执行文件存在: ${soga_dir}/soga${plain}"
    fi
    
    # 检查服务文件
    if [[ ! -f "/etc/systemd/system/${instance_name}.service" ]]; then
        echo -e "${red}✗ 服务文件不存在: /etc/systemd/system/${instance_name}.service${plain}"
        has_error=1
    else
        echo -e "${green}✓ 服务文件存在: /etc/systemd/system/${instance_name}.service${plain}"
        # 检查服务文件中的路径
        local service_path=$(grep "ExecStart=" /etc/systemd/system/${instance_name}.service 2>/dev/null | cut -d'=' -f2 | cut -d' ' -f1)
        if [[ "$service_path" != "${soga_dir}/soga" ]]; then
            echo -e "${yellow}⚠ 服务文件中的路径不正确: ${service_path}${plain}"
            echo -e "${yellow}  应该是: ${soga_dir}/soga${plain}"
            has_error=1
        else
            echo -e "${green}✓ 服务文件路径正确${plain}"
        fi
    fi
    
    # 检查配置目录
    if [[ ! -d "$config_dir" ]]; then
        echo -e "${yellow}⚠ 配置目录不存在: ${config_dir}${plain}"
    else
        echo -e "${green}✓ 配置目录存在: ${config_dir}${plain}"
    fi
    
    # 检查管理脚本
    if [[ ! -f "/usr/bin/${instance_name}" ]]; then
        echo -e "${yellow}⚠ 管理脚本不存在: /usr/bin/${instance_name}${plain}"
    else
        echo -e "${green}✓ 管理脚本存在: /usr/bin/${instance_name}${plain}"
    fi
    
    echo ""
    if [[ $has_error -eq 1 ]]; then
        echo -e "${red}${instance_name} 文件不完整，需要修复！${plain}"
        return 1
    else
        echo -e "${green}${instance_name} 文件完整！${plain}"
        return 0
    fi
}

# 修复管理脚本（重新生成以确保配置正确）
fix_management_script() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${blue}开始修复 ${instance_name} 管理脚本...${plain}"
    echo -e "${yellow}实例名称: ${instance_name}${plain}"
    
    # 确定正确的路径（严格基于实例名称）
    local soga_dir="/usr/local/${instance_name}"
    local config_dir="/etc/${instance_name}"
    
    # 特殊处理：第一个实例可能使用 soga 而不是 soga1
    if [[ "$instance_name" == "soga" ]]; then
        soga_dir="/usr/local/soga"
        config_dir="/etc/soga"
    fi
    
    echo -e "${yellow}程序目录: ${soga_dir}${plain}"
    echo -e "${yellow}配置目录: ${config_dir}${plain}"
    echo ""
    
    # 验证目录是否存在
    if [[ ! -d "$soga_dir" ]]; then
        echo -e "${red}错误: ${soga_dir} 目录不存在${plain}"
        echo -e "${yellow}如果程序文件丢失，请重新安装 ${instance_name}${plain}"
        wait_for_enter
        return 1
    fi
    
    # 检查可执行文件
    if [[ ! -f "${soga_dir}/soga" ]]; then
        echo -e "${red}错误: ${soga_dir}/soga 可执行文件不存在${plain}"
        echo -e "${yellow}如果程序文件丢失，请重新安装 ${instance_name}${plain}"
        wait_for_enter
        return 1
    fi
    
    # 验证路径一致性
    if [[ "$soga_dir" != "/usr/local/${instance_name}" ]] && [[ ! ("$instance_name" == "soga" && "$soga_dir" == "/usr/local/soga") ]]; then
        echo -e "${red}错误: 路径不一致！${plain}"
        echo -e "${red}实例名称: ${instance_name}${plain}"
        echo -e "${red}程序目录: ${soga_dir}${plain}"
        wait_for_enter
        return 1
    fi
    
    # 重新生成管理脚本
    install_management_script ${instance_name} ${soga_dir} ${config_dir}
    
    echo -e "${green}${instance_name} 管理脚本已修复！${plain}"
    echo -e "${green}配置目录: ${config_dir}${plain}"
    echo -e "${green}程序目录: ${soga_dir}${plain}"
    echo -e "${green}管理命令: /usr/bin/${instance_name}${plain}"
    
    wait_for_enter
}

# 修复服务文件
fix_service_file() {
    local instance_name=$1
    
    if ! is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 未安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${blue}开始修复 ${instance_name} 服务文件...${plain}"
    
    # 确定正确的路径
    local soga_dir="/usr/local/${instance_name}"
    local config_dir="/etc/${instance_name}"
    
    if [[ "$instance_name" == "soga" ]]; then
        soga_dir="/usr/local/soga"
        config_dir="/etc/soga"
    fi
    
    # 检查程序文件是否存在
    if [[ ! -f "${soga_dir}/soga" ]]; then
        echo -e "${red}错误: ${soga_dir}/soga 可执行文件不存在${plain}"
        echo -e "${yellow}请先重新安装 ${instance_name}${plain}"
        wait_for_enter
        return 1
    fi
    
    # 检查是否有原始服务文件模板
    if [[ -f "${soga_dir}/soga.service" ]]; then
        echo -e "${yellow}使用原始服务文件模板...${plain}"
        # 修改服务文件中的路径
        sed -i "s|/usr/local/soga|${soga_dir}|g" ${soga_dir}/soga.service
        sed -i "s|/etc/soga|${config_dir}|g" ${soga_dir}/soga.service
        sed -i "s|Description=soga|Description=${instance_name}|g" ${soga_dir}/soga.service
        sed -i "s|ExecStart=/usr/local/soga/soga|ExecStart=${soga_dir}/soga|g" ${soga_dir}/soga.service
        
        # 确保 WorkingDirectory 指向配置目录
        if grep -q "WorkingDirectory=" ${soga_dir}/soga.service; then
            sed -i "s|WorkingDirectory=.*|WorkingDirectory=${config_dir}|g" ${soga_dir}/soga.service
        else
            # 如果没有 WorkingDirectory，在 [Service] 部分添加
            sed -i "/\[Service\]/a WorkingDirectory=${config_dir}" ${soga_dir}/soga.service
        fi
        
        # 复制服务文件
        cp -f ${soga_dir}/soga.service /etc/systemd/system/${instance_name}.service
        systemctl daemon-reload
        
        echo -e "${green}${instance_name} 服务文件已修复！${plain}"
    else
        echo -e "${yellow}未找到原始服务文件模板，手动创建...${plain}"
        
        # 手动创建服务文件 - WorkingDirectory 必须指向配置目录
        cat > /etc/systemd/system/${instance_name}.service << EOF
[Unit]
Description=${instance_name} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${config_dir}
ExecStart=${soga_dir}/soga
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        echo -e "${green}${instance_name} 服务文件已创建！${plain}"
    fi
    
    # 尝试启动服务
    systemctl enable ${instance_name}
    systemctl restart ${instance_name}
    sleep 2
    
    if systemctl is-active --quiet ${instance_name}; then
        echo -e "${green}${instance_name} 服务已成功启动！${plain}"
    else
        echo -e "${yellow}${instance_name} 服务可能启动失败，请检查日志${plain}"
        echo -e "${yellow}使用命令查看: systemctl status ${instance_name}${plain}"
    fi
    
    wait_for_enter
}

# 等待回车
wait_for_enter() {
    echo ""
    echo -n -e "${yellow}按回车返回主菜单: ${plain}"
    read temp
}

# 安装实例
install_instance_menu() {
    local instance_num=$1
    local instance_name="soga${instance_num}"
    
    if [[ $instance_num -eq 1 ]]; then
        instance_name="soga"
    fi
    
    if is_instance_installed ${instance_name}; then
        echo -e "${red}${instance_name} 已安装！${plain}"
        wait_for_enter
        return 1
    fi
    
    echo -e "${blue}开始安装 ${instance_name}...${plain}"
    install_base
    install_acme
    install_soga ${instance_num} ""
    echo -e "${green}${instance_name} 安装完成！${plain}"
    wait_for_enter
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${blue}========================================${plain}"
    echo -e "${green}        soga 多实例管理脚本${plain}"
    echo -e "${blue}========================================${plain}"
    echo ""
    echo -e "${green}【安装选项】${plain}"
    echo -e "  ${green}1.${plain} 安装 soga"
    echo -e "  ${green}2.${plain} 安装 soga2"
    echo -e "  ${green}3.${plain} 安装 soga3"
    echo -e "  ${green}4.${plain} 安装 soga4"
    echo ""
    echo -e "${green}【配置选项】${plain}"
    echo -e "  ${green}5.${plain} 配置默认 soga 配置"
    echo -e "  ${green}6.${plain} 配置默认 soga2 配置"
    echo -e "  ${green}7.${plain} 自定义配置"
    echo ""
    echo -e "${green}【重启选项】${plain}"
    echo -e "  ${green}8.${plain} 重新启动 soga"
    echo -e "  ${green}9.${plain} 重新启动 soga2"
    echo -e "  ${green}10.${plain} 重新启动 soga3"
    echo -e "  ${green}11.${plain} 重新启动 soga4"
    echo ""
    echo -e "${green}【日志选项】${plain}"
    echo -e "  ${green}12.${plain} 查看 soga 日志"
    echo -e "  ${green}13.${plain} 查看 soga2 日志"
    echo -e "  ${green}14.${plain} 查看 soga3 日志"
    echo -e "  ${green}15.${plain} 查看 soga4 日志"
    echo ""
    echo -e "${green}【卸载选项】${plain}"
    echo -e "  ${green}16.${plain} 卸载 soga"
    echo -e "  ${green}17.${plain} 卸载 soga2"
    echo -e "  ${green}18.${plain} 卸载 soga3"
    echo -e "  ${green}19.${plain} 卸载 soga4"
    echo ""
    echo -e "${green}【修复选项】${plain}"
    echo -e "  ${green}20.${plain} 检查 soga 文件完整性"
    echo -e "  ${green}21.${plain} 检查 soga2 文件完整性"
    echo -e "  ${green}22.${plain} 修复 soga 服务文件"
    echo -e "  ${green}23.${plain} 修复 soga2 服务文件"
    echo -e "  ${green}24.${plain} 修复 soga 管理脚本"
    echo -e "  ${green}25.${plain} 修复 soga2 管理脚本"
    echo ""
    echo -e "  ${green}0.${plain} 退出脚本"
    echo ""
    echo -e "${blue}========================================${plain}"
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
        read -p "请输入选择 [0-25]: " choice
        
        case "${choice}" in
        1)
            install_instance_menu 1
            ;;
        2)
            install_instance_menu 2
            ;;
        3)
            install_instance_menu 3
            ;;
        4)
            install_instance_menu 4
            ;;
        5)
            config_instance_default "soga" 1
            ;;
        6)
            config_instance_default "soga2" 2
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
            restart_instance "soga"
            ;;
        9)
            restart_instance "soga2"
            ;;
        10)
            restart_instance "soga3"
            ;;
        11)
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
            check_instance_files "soga"
            wait_for_enter
            ;;
        21)
            check_instance_files "soga2"
            wait_for_enter
            ;;
        22)
            fix_service_file "soga"
            ;;
        23)
            fix_service_file "soga2"
            ;;
        24)
            fix_management_script "soga"
            ;;
        25)
            fix_management_script "soga2"
            ;;
        0)
            echo -e "${green}退出脚本${plain}"
            exit 0
            ;;
        *)
            echo -e "${red}请输入正确的数字 [0-25]${plain}"
            sleep 2
            ;;
        esac
    done
}

# 执行主函数
main $1
