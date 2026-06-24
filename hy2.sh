#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Hysteria2 极简部署脚本（证书指纹 pinSha256 版 + 修复 SANs 问题）

set -e

# ---------- 默认配置 ----------
HYSTERIA_VERSION="v2.6.5"
DEFAULT_PORT=22222
AUTH_PASSWORD="***"
CERT_FILE="cert.pem"
KEY_FILE="key.pem"
SNI="www.bing.com"
ALPN="h3"
# ------------------------------

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Hysteria2 极简部署脚本 - pinSha256 兼容版 (已修复 SANs)"
echo "支持命令行端口参数，如：bash hy2-fixed.sh 443"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if [[ $# -ge 1 && -n "${1:-}" ]]; then
    SERVER_PORT="$1"
    echo "✅ 使用命令行指定端口: $SERVER_PORT"
else
    SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
    echo "⚙️ 使用默认端口: $SERVER_PORT"
fi

arch_name() {
    local machine
    machine=$(uname -m | tr '[:upper:]' '[:lower:]')
    if [[ "$machine" == *"arm64"* ]] || [[ "$machine" == *"aarch64"* ]]; then
        echo "arm64"
    elif [[ "$machine" == *"x86_64"* ]] || [[ "$machine" == *"amd64"* ]]; then
        echo "amd64"
    else
        echo ""
    fi
}

ARCH=$(arch_name)
[ -z "$ARCH" ] && { echo "❌ 无法识别 CPU 架构"; exit 1; }

BIN_NAME="hysteria-linux-${ARCH}"
BIN_PATH="./${BIN_NAME}"

download_binary() {
    [ -f "$BIN_PATH" ] && { echo "✅ 二进制已存在"; return; }
    URL="https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/${BIN_NAME}"
    echo "⏳ 下载: $URL"
    curl -L --retry 3 --connect-timeout 30 -o "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    echo "✅ 下载完成"
}

ensure_cert() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "✅ 使用现有证书"
        return
    fi
    echo "🔑 生成自签证书（prime256v1，带 SANs）..."
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=${SNI}" \
        -addext "subjectAltName=DNS:${SNI}"
    echo "✅ 证书生成成功（含 SANs）"
}

calc_pinsha256() {
    openssl x509 -in "$CERT_FILE" -outform der | openssl dgst -sha256 -binary | base64
}

write_config() {
cat > server.yaml <<EOF
listen: ":${SERVER_PORT}"
tls:
  cert: "$(pwd)/${CERT_FILE}"
  key: "$(pwd)/${KEY_FILE}"
  alpn:
    - "${ALPN}"
auth:
  type: "password"
  password: "${AUTH_PASSWORD}"
bandwidth:
  up: "200mbps"
  down: "200mbps"
quic:
  max_idle_timeout: "10s"
  max_concurrent_streams: 4
  initial_stream_receive_window: 65536
  max_stream_receive_window: 131072
  initial_conn_receive_window: 131072
  max_conn_receive_window: 262144
EOF
    echo "✅ 写入 server.yaml"
}

get_server_ip() {
    curl -s --max-time 10 https://api.ipify.org || echo "YOUR_SERVER_IP"
}

print_connection_info() {
    local IP="$1"
    local FINGERPRINT
    FINGERPRINT=$(calc_pinsha256)
    echo "🎉 Hysteria2 部署成功！（证书指纹版，已修复 SANs）"
    echo "=========================================================================="
    echo "📋 服务器信息:"
    echo "   🌐 IP地址: $IP"
    echo "   🔌 端口: $SERVER_PORT"
    echo "   🔑 密码: $AUTH_PASSWORD"
    echo "   🔐 证书指纹 (pinSha256): $FINGERPRINT"
    echo ""
    echo "📱 节点链接（复制下面这行导入 v2rayNG）:"
    echo "hysteria2://${AUTH_PASSWORD}@${IP}:${SERVER_PORT}?sni=${SNI}&alpn=${ALPN}&pinSha256=${FINGERPRINT}#Hy2-Bing"
    echo ""
    echo "📄 客户端配置:"
    echo "  server: ${IP}:${SERVER_PORT}"
    echo "  auth: ${AUTH_PASSWORD}"
    echo "  tls:"
    echo "    sni: ${SNI}"
    echo "    alpn: [\"${ALPN}\"]"
    echo "    pinSha256: ${FINGERPRINT}"
    echo "=========================================================================="
}

main() {
    download_binary
    ensure_cert
    write_config
    SERVER_IP=$(get_server_ip)
    print_connection_info "$SERVER_IP"
    echo "🚀 启动 Hysteria2 服务器..."
    exec "$BIN_PATH" server -c server.yaml
}

main "$@"
