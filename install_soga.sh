#!/bin/bash

    # 提示用户选择安装源
    echo "请选择安装源："
    echo "1. GitHub"
    echo "2. Gitee"
    read -p "请输入选项 (1/2)：" choice

    # 根据选择执行相应的安装命令
    case $choice in
        1)
            echo "使用GitHub源安装..."
            bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/soga/master/install.sh)
            ;;
        2)
            echo "使用Gitee源安装..."
            bash <(curl -Ls https://gitee.com/georgeeasop/img/raw/master/install.sh)
            ;;
        *)
            echo "无效的选项，脚本退出。"
            exit 1
            ;;
    esac

    # 提示用户输入node_id
    read -p "请输入node_id (数字)：" node_id

    # 验证输入是否为数字
    if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
        echo "错误：node_id必须是数字！"
        exit 1
    fi

    # 配置soga
    echo "配置soga..."
    soga config type=xboard server_type=ss node_id=$node_id soga_key=5SrOk5VxovqomAVgKAIKBXGednyRpMSw webapi_url=https://vowa.top/ webapi_key=M2X84M6a7N0iGHWC8fU7p8bwrVcCBmz

    # 重启soga服务
    echo "重启soga服务..."
    soga restart

    echo "操作完成！"
    
