#!/bin/bash
# ==================================================
# Cloudflare DNS + acme.sh
# 主域名 + *.通配符
# 自动缓存参数，失败可直接重跑
# 默认 Let’s Encrypt（ZeroSSL 已放弃）
# ==================================================

set -e

# ---------- root 检查 ----------
[ "$EUID" -ne 0 ] && echo "请使用 root 执行" && exit 1

# ---------- 配置文件 ----------
CONF_DIR="/root/.acme-auto"
CONF_FILE="$CONF_DIR/config"
CERT_DIR="/root/cert"
LOG_FILE="$CERT_DIR/acme.log"

mkdir -p "$CONF_DIR" "$CERT_DIR"

# ---------- 读取或输入参数 ----------
if [ -f "$CONF_FILE" ]; then
  source "$CONF_FILE"
  echo "[INFO] 已读取缓存配置：$CONF_FILE"
else
  read -p "请输入 Cloudflare API Token: " CF_Token
  read -p "请输入主域名 (如 example.com): " DOMAIN
  read -p "请输入邮箱 (用于 LE 注册): " ACME_EMAIL

  cat >"$CONF_FILE" <<EOF
export CF_Token="$CF_Token"
export DOMAIN="$DOMAIN"
export ACME_EMAIL="$ACME_EMAIL"
EOF

  chmod 600 "$CONF_FILE"
fi

source "$CONF_FILE"

# ---------- 安装 acme.sh ----------
if [ ! -f /root/.acme.sh/acme.sh ]; then
  curl https://get.acme.sh | sh
fi

export PATH="$PATH:/root/.acme.sh"

# ---------- 注册账号（LE） ----------
/root/.acme.sh/acme.sh \
  --register-account \
  -m "$ACME_EMAIL" \
  --server letsencrypt \
  >>"$LOG_FILE" 2>&1 || true

# ---------- 签发函数 ----------
issue() {
  local KEYLEN="$1"

  echo "[INFO] 签发 $DOMAIN + *.$DOMAIN | key=$KEYLEN"

  /root/.acme.sh/acme.sh \
    --issue \
    --dns dns_cf \
    -d "$DOMAIN" \
    -d "*.$DOMAIN" \
    --keylength "$KEYLEN" \
    --server letsencrypt \
    --dnssleep 60 \
    >>"$LOG_FILE" 2>&1
}

# ---------- ECC → RSA ----------
if issue ec-256; then
  CERT_SUFFIX="_ecc"
else
  echo "[WARN] ECC 失败，切换 RSA"
  issue 4096
  CERT_SUFFIX=""
fi

# ---------- 安装证书 ----------
/root/.acme.sh/acme.sh \
  --install-cert \
  -d "$DOMAIN" \
  --key-file "$CERT_DIR/private.key" \
  --fullchain-file "$CERT_DIR/public.crt" \
  ${CERT_SUFFIX:+--ecc} \
  >>"$LOG_FILE" 2>&1

chmod 600 "$CERT_DIR/private.key"
chmod 644 "$CERT_DIR/public.crt"

# ---------- 自动续期 ----------
/root/.acme.sh/acme.sh --install-cronjob >>"$LOG_FILE" 2>&1

echo
echo "===================================="
echo "✅ 证书签发成功"
echo "私钥: $CERT_DIR/private.key"
echo "证书: $CERT_DIR/public.crt"
echo "日志: $LOG_FILE"
echo "===================================="
