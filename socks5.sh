DEFAULT_SOCKS_PORT=20000                         # SOCKS5默认起始端口
DEFAULT_HTTP_PORT=30000                          # HTTP默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   # 默认账号
DEFAULT_SOCKS_PASSWORD="passwordb"               # 默认密码
MAX_IPS_PER_CONFIG=50                           # 每个配置文件最多IP数

IP_ADDRESSES=($(hostname -I))
TOTAL_IPS=${#IP_ADDRESSES[@]}

install_xray() {
    echo "安装 Xray..."
    apt-get install unzip -y || yum install unzip -y
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
    unzip Xray-linux-64.zip
    mv xray /usr/local/bin/xrayL
    chmod +x /usr/local/bin/xrayL
    echo "Xray 安装完成."
}

config_proxy() {
    mkdir -p /etc/xrayL
    
    read -p "SOCKS5起始端口 (默认 $DEFAULT_SOCKS_PORT): " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-$DEFAULT_SOCKS_PORT}
    
    read -p "HTTP起始端口 (默认 $DEFAULT_HTTP_PORT): " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
    
    read -p "代理账号 (默认 $DEFAULT_SOCKS_USERNAME): " PROXY_USERNAME
    PROXY_USERNAME=${PROXY_USERNAME:-$DEFAULT_SOCKS_USERNAME}
    
    read -p "代理密码 (默认 $DEFAULT_SOCKS_PASSWORD): " PROXY_PASSWORD
    PROXY_PASSWORD=${PROXY_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}
    
    # 计算需要多少个配置文件
    CONFIG_COUNT=$(( (TOTAL_IPS + MAX_IPS_PER_CONFIG - 1) / MAX_IPS_PER_CONFIG ))
    
    for ((config_num=0; config_num<CONFIG_COUNT; config_num++)); do
        config_content=""
        start_index=$((config_num * MAX_IPS_PER_CONFIG))
        end_index=$((start_index + MAX_IPS_PER_CONFIG))
        
        if [ $end_index -gt $TOTAL_IPS ]; then
            end_index=$TOTAL_IPS
        fi
        
        for ((i=start_index; i<end_index; i++)); do
            # SOCKS5配置
            config_content+="[[inbounds]]\n"
            config_content+="port = $((SOCKS_PORT + i))\n"
            config_content+="protocol = \"socks\"\n"
            config_content+="tag = \"socks_$((i + 1))\"\n"
            config_content+="[inbounds.settings]\n"
            config_content+="auth = \"password\"\n"
            config_content+="udp = true\n"
            config_content+="ip = \"${IP_ADDRESSES[i]}\"\n"
            config_content+="[[inbounds.settings.accounts]]\n"
            config_content+="user = \"$PROXY_USERNAME\"\n"
            config_content+="pass = \"$PROXY_PASSWORD\"\n\n"
            
            # HTTP配置
            config_content+="[[inbounds]]\n"
            config_content+="port = $((HTTP_PORT + i))\n"
            config_content+="protocol = \"http\"\n"
            config_content+="tag = \"http_$((i + 1))\"\n"
            config_content+="[inbounds.settings]\n"
            config_content+="auth = \"password\"\n"
            config_content+="ip = \"${IP_ADDRESSES[i]}\"\n"
            config_content+="[[inbounds.settings.accounts]]\n"
            config_content+="user = \"$PROXY_USERNAME\"\n"
            config_content+="pass = \"$PROXY_PASSWORD\"\n\n"
            
            # 出站配置
            config_content+="[[outbounds]]\n"
            config_content+="sendThrough = \"${IP_ADDRESSES[i]}\"\n"
            config_content+="protocol = \"freedom\"\n"
            config_content+="tag = \"out_$((i + 1))\"\n\n"
            
            # 路由规则
            config_content+="[[routing.rules]]\n"
            config_content+="type = \"field\"\n"
            config_content+="inboundTag = [\"socks_$((i + 1))\", \"http_$((i + 1))\"]\n"
            config_content+="outboundTag = \"out_$((i + 1))\"\n\n"
        done
        
        # 保存配置文件
        echo -e "$config_content" >/etc/xrayL/config_${config_num}.toml
        
        # 创建对应的服务
        cat <<EOF >/etc/systemd/system/xrayL_${config_num}.service
[Unit]
Description=XrayL Service ${config_num}
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config_${config_num}.toml
Restart=on-failure
User=root
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable xrayL_${config_num}.service
        systemctl start xrayL_${config_num}.service
    done
    
    echo ""
    echo "代理配置完成"
    echo "总IP数量: $TOTAL_IPS"
    echo "配置文件数量: $CONFIG_COUNT"
    echo "SOCKS5端口范围: $SOCKS_PORT - $((SOCKS_PORT + TOTAL_IPS - 1))"
    echo "HTTP端口范围: $HTTP_PORT - $((HTTP_PORT + TOTAL_IPS - 1))"
    echo "代理账号: $PROXY_USERNAME"
    echo "代理密码: $PROXY_PASSWORD"
    echo ""
}

main() {
    [ -x "$(command -v xrayL)" ] || install_xray
    config_proxy
}

main "$@"
