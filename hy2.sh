#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Hysteria2 极简部署脚本（支持命令行端口参数 + 证书指纹 pinSha256 验证）
# 适用于超低内存环境（32-64MB）
# v2rayNG 兼容版：使用 pinSha256 替代已废弃的 insecure=1

set -e

# ---------- 默认配置 ----------
HYSTERIA_VERSION="v2.6.5"
DEFAULT_PORT=22222         # 自适应端口
AUTH_PASSWORD="rZaFUbt7etvzgpQ20mCp"   # 建议修改为复杂密码
CERT_FILE="cert.pem"
KEY_FILE="key.pem"
SNI="www.bing.com"
ALPN="h3"
# ------------------------------

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Hysteria2 极简部署脚本（Shell 版）"
echo "支持命令行端口参数，如：bash hysteria2.sh 443"
echo "证书指纹 (pinSha256) 版 —— 兼容 v2rayNG 2026 新规"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# ---------- 获取端口 ----------
if [[ $# -ge 1 && -n "${1:-}" ]]; then
    SERVER_PORT="$1"
    echo "✅ 使用命令行指定端口: $SERVER_PORT"
else
    SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
    echo "⚙️ 未提供端口参数，使用默认端口: $SERVER_PORT"
fi

# ---------- 检测架构 ----------
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
if [ -z "$ARCH" ]; then
  echo "❌ 无法识别 CPU 架构: $(uname -m)"
  exit 1
fi

BIN_NAME="hysteria-linux-${ARCH}"
BIN_PATH="./${BIN_NAME}"

# ---------- 下载二进制 ----------
download_binary() {
    if [ -f "$BIN_PATH" ]; then
        echo "✅ 二进制已存在，跳过下载。"
        return
    fi
    URL="https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/${BIN_NAME}"
    echo "⏳ 下载: $URL"
    curl -L --retry 3 --connect-timeout 30 -o "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    echo "✅ 下载完成并设置可执行: $BIN_PATH"
}

# ---------- 生成证书 ----------
ensure_cert() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "✅ 发现证书，使用现有 cert/key。"
        return
    fi
    echo "🔑 未发现证书，使用 openssl 生成自签证书（prime256v1）..."
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=${SNI}"
    echo "✅ 证书生成成功。"
}

# ---------- 计算证书指纹 (pinSha256) ----------
calc_pinsha256() {
    openssl x509 -in "$CERT_FILE" -outform der | openssl dgst -sha256 -binary | base64
}

# ---------- 写配置文件 ----------
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
    echo "✅ 写入配置 server.yaml（端口=${SERVER_PORT}, SNI=${SNI}, ALPN=${ALPN}）。"
}

# ---------- 获取服务器 IP ----------
get_server_ip() {
    IP=$(curl -s --max-time 10 https://api.ipify.org || echo "YOUR_SERVER_IP")
    echo "$IP"
}

# ---------- 打印连接信息 ----------
print_connection_info() {
    local IP="$1"
    local FINGERPRINT
    FINGERPRINT=$(calc_pinsha256)
    echo "🎉 Hysteria2 部署成功！（证书指纹版）"
    echo "=========================================================================="
    echo "📋 服务器信息:"
    echo "   🌐 IP地址: $IP"
    echo "   🔌 端口: $SERVER_PORT"
    echo "   🔑 密码: $AUTH_PASSWORD"
    echo "   🔐 证书指纹 (pinSha256): $FINGERPRINT"
    echo ""
    echo "📱 节点链接（SNI=${SNI}, ALPN=${ALPN}, pinSha256 验证）:"
    echo "hysteria2://${AUTH_PASSWORD}@${IP}:${SERVER_PORT}?sni=${SNI}&alpn=${ALPN}&pinSha256=${FINGERPRINT}#Hy2-Bing"
    echo ""
    echo "📄 客户端配置文件:"
    echo "server: ${IP}:${SERVER_PORT}"
    echo "auth: ${AUTH_PASSWORD}"
    echo "tls:"
    echo "  sni: ${SNI}"
    echo "  alpn: [\"${ALPN}\"]"
    echo "  pinSha256: ${FINGERPRINT}"
    echo "socks5:"
    echo "  listen: 127.0.0.1:1080"
    echo "http:"
    echo "  listen: 127.0.0.1:8080"
    echo "=========================================================================="
    echo "💡 将此链接或配置导入 v2rayNG 即可，不再弹出 insecure 警告。"
}

# ---------- 主逻辑 ----------
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
