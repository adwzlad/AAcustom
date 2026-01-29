#!/bin/bash
# ========================================
# Cloudflare DNS-01 稳定版通配符证书签发脚本
# acme.sh + ZeroSSL
# 解决：TXT 提前清理 / 重复输入 / 时序翻车
# ========================================

set -e

CONF_FILE="/root/.acme_cf_env"
CERT_DIR="/root/cert"
LOG_PATH="${CERT_DIR}/acme.sh.log"

# ========= root 检查 =========
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] 请使用 root 执行：sudo -i"
  exit 1
fi

mkdir -p "$CERT_DIR"

# ========= 读取 / 写入配置 =========
if [ -f "$CONF_FILE" ]; then
  source "$CONF_FILE"
  echo "[INFO] 已加载历史配置：$CONF_FILE"
else
  read -p "请输入 Cloudflare API Token: " CF_Token
  read -p "请输入主域名 (例如 a.com): " DOMAIN
  read -p "请输入邮箱 (用于 ZeroSSL 注册): " ACME_EMAIL

  cat >"$CONF_FILE" <<EOF
export CF_Token="$CF_Token"
export DOMAIN="$DOMAIN"
export ACME_EMAIL="$ACME_EMAIL"
EOF

  chmod 600 "$CONF_FILE"
  source "$CONF_FILE"
  echo "[INFO] 配置已保存，下次无需重复输入"
fi

export CF_Token

# ========= 安装 acme.sh =========
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
  echo "[INFO] 安装 acme.sh ..."
  curl -s https://get.acme.sh | sh
fi

export PATH="$PATH:/root/.acme.sh"

# ========= 注册账号（幂等） =========
echo "[INFO] 注册 / 确认 ZeroSSL 账号..."
acme.sh --register-account -m "$ACME_EMAIL" --server zerossl >>"$LOG_PATH" 2>&1 || true

# ========= 签发证书（关键部分） =========
echo "[INFO] 开始签发 ${DOMAIN} 和 *.${DOMAIN}"
echo "[INFO] 使用 ZeroSSL + ECC + DNS-01"

acme.sh --issue \
  --dns dns_cf \
  -d "${DOMAIN}" \
  -d "*.${DOMAIN}" \
  --keylength ec-256 \
  --dnssleep 180 \
  --server zerossl \
  --debug \
  >>"$LOG_PATH" 2>&1

# ========= 安装证书 =========
echo "[INFO] 安装证书到 ${CERT_DIR}"

acme.sh --install-cert -d "${DOMAIN}" \
  --ecc \
  --key-file       "${CERT_DIR}/private.key" \
  --fullchain-file "${CERT_DIR}/public.crt" \
  >>"$LOG_PATH" 2>&1

chmod 600 "${CERT_DIR}/private.key"
chmod 644 "${CERT_DIR}/public.crt"

# ========= 自动续期 =========
acme.sh --install-cronjob >>"$LOG_PATH" 2>&1

echo "========================================"
echo "[SUCCESS] 证书签发并安装完成 🎉"
echo "私钥: ${CERT_DIR}/private.key"
echo "证书: ${CERT_DIR}/public.crt"
echo "日志: ${LOG_PATH}"
echo "========================================"
