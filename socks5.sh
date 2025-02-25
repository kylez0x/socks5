DEFAULT_START_PORT=20000                         #默认socks5起始端口
DEFAULT_SOCKS_USERNAME="userb"                   #默认socks账号
DEFAULT_SOCKS_PASSWORD="passwordb"               #默认socks密码
DEFAULT_WS_PATH="/ws"                            #默认ws路径
DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid) #默认随机UUID
DEFAULT_HTTP_PORT=30000                          #默认http代理起始端口

IP_ADDRESSES=($(hostname -I))

install_xray() {
    echo "安装 Xray..."
    apt-get install unzip -y || yum install unzip -y
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
    unzip Xray-linux-64.zip
    mv xray /usr/local/bin/xrayL
    chmod +x /usr/local/bin/xrayL
    cat <<EOF >/etc/systemd/system/xrayL.service
[Unit]
Description=XrayL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config.toml
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xrayL.service
    systemctl start xrayL.service
    echo "Xray 安装完成."
}

config_xray() {
    config_type=$1
    mkdir -p /etc/xrayL
    if [ "$config_type" != "socks" ] && [ "$config_type" != "vmess" ] && [ "$config_type" != "http" ]; then
        echo "类型错误！仅支持socks、vmess和http."
        exit 1
    fi

    # SOCKS5 配置部分
    read -p "SOCKS 起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}
    read -p "SOCKS 账号 (默认 $DEFAULT_SOCKS_USERNAME): " SOCKS_USERNAME
    SOCKS_USERNAME=${SOCKS_USERNAME:-$DEFAULT_SOCKS_USERNAME}

    read -p "SOCKS 密码 (默认 $DEFAULT_SOCKS_PASSWORD): " SOCKS_PASSWORD
    SOCKS_PASSWORD=${SOCKS_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}

    # HTTP 配置部分
    read -p "HTTP 起始端口 (默认 $DEFAULT_HTTP_PORT): " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}

    for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
        # SOCKS 配置
        config_content+="[[inbounds]]\n"
        config_content+="port = $((START_PORT + i))\n"
        config_content+="protocol = \"socks\"\n"
        config_content+="tag = \"tag_socks_$((i + 1))\"\n"
        config_content+="[inbounds.settings]\n"
        config_content+="auth = \"password\"\n"
        config_content+="udp = true\n"
        config_content+="ip = \"${IP_ADDRESSES[i]}\"\n"
        config_content+="[[inbounds.settings.accounts]]\n"
        config_content+="user = \"$SOCKS_USERNAME\"\n"
        config_content+="pass = \"$SOCKS_PASSWORD\"\n"

        # HTTP 配置
        config_content+="[[inbounds]]\n"
        config_content+="port = $((HTTP_PORT + i))\n"
        config_content+="protocol = \"http\"\n"
        config_content+="tag = \"tag_http_$((i + 1))\"\n"
        config_content+="[inbounds.settings]\n"
        config_content+="ip = \"${IP_ADDRESSES[i]}\"\n"

        # 出站配置
        config_content+="[[outbounds]]\n"
        config_content+="sendThrough = \"${IP_ADDRESSES[i]}\"\n"
        config_content+="protocol = \"freedom\"\n"
        config_content+="tag = \"tag_$((i + 1))\"\n\n"
        config_content+="[[routing.rules]]\n"
        config_content+="type = \"field\"\n"
        config_content+="inboundTag = \"tag_socks_$((i + 1))\"\n"
        config_content+="outboundTag = \"tag_$((i + 1))\"\n\n"

        config_content+="[[routing.rules]]\n"
        config_content+="type = \"field\"\n"
        config_content+="inboundTag = \"tag_http_$((i + 1))\"\n"
        config_content+="outboundTag = \"tag_$((i + 1))\"\n\n\n"
    done

    echo -e "$config_content" >/etc/xrayL/config.toml
    systemctl restart xrayL.service
    systemctl --no-pager status xrayL.service
    echo ""
    echo "生成 SOCKS5 和 HTTP 配置完成"
    echo "SOCKS起始端口:$START_PORT"
    echo "HTTP起始端口:$HTTP_PORT"
    echo "结束端口:$(($START_PORT + $i - 1))"
    echo ""
}

main() {
    [ -x "$(command -v xrayL)" ] || install_xray
    config_xray "socks" # 生成socks5和http代理配置
}

main "$@"
