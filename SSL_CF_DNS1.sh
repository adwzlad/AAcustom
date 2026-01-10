#!/bin/bash
# ========================================
# 增强版一键签发 主域名 + *.域名 通配符证书
# 使用 acme.sh + ECC/RSA，支持 ZeroSSL 与 Let’s Encrypt
# 自动注册账号，支持 Cloudflare DNS
# ========================================

set -e

# ========== 检查 root ==========
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] 请使用 root 权限执行：sudo -i"
  exit 1
fi

# ========== 输入 Cloudflare Token ==========
if [ -n "$CF_Token" ]; then
  echo "[INFO] 检测到已有 Cloudflare API Token: ${CF_Token:0:10}******"
  read -p "是否使用此 Token？(Y/n): " use_old
  case "$use_old" in
    [nN]*) read -p "请输入新的 Cloudflare API Token: " CF_Token ;;
    *) echo "[INFO] 继续使用现有 Token" ;;
  esac
else
  read -p "请输入 Cloudflare API Token: " CF_Token
fi
export CF_Token

# ========== 输入域名与邮箱 ==========
read -p "请输入主域名 (例如 a.com): " DOMAIN
read -p "请输入邮箱 (用于 ZeroSSL/LE 注册): " ACME_EMAIL

# ========== 创建证书目录 ==========
CERT_DIR="/root/cert"
mkdir -p "${CERT_DIR}"
KEY_PATH="${CERT_DIR}/private.key"
CERT_PATH="${CERT_DIR}/public.crt"
LOG_PATH="${CERT_DIR}/acme.sh.log"

# ========== 安装 acme.sh ==========
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
  echo "[INFO] acme.sh 未安装，正在安装..."
  curl https://get.acme.sh | sh
fi

export PATH=$PATH:/root/.acme.sh
source /root/.bashrc 2>/dev/null || true

# ========== 注册账号 ==========
echo "[INFO] 注册 ZeroSSL / Let’s Encrypt 账号..."
/root/.acme.sh/acme.sh --register-account -m "$ACME_EMAIL" >>"$LOG_PATH" 2>&1 || true

# ========== 签发函数 ==========
issue_cert() {
  local KEYLEN="$1"
  local CA="$2"

  echo "[INFO] 开始签发 ${DOMAIN} 和 *.${DOMAIN}，Key: $KEYLEN, CA: $CA"
  
  if ! /root/.acme.sh/acme.sh \
    --issue --dns dns_cf -d "${DOMAIN}" -d "*.${DOMAIN}" \
    --keylength "$KEYLEN" --server "$CA" --dnssleep 60 --debug >>"$LOG_PATH" 2>&1; then
    return 1
  fi

  echo "[INFO] 安装证书到 ${CERT_DIR} ..."
  /root/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" \
    --key-file "${KEY_PATH}" \
    --fullchain-file "${CERT_PATH}" \
    --ecc 2>/dev/null >>"$LOG_PATH" 2>&1 || true

  chmod 600 "${KEY_PATH}" 2>/dev/null
  chmod 644 "${CERT_PATH}" 2>/dev/null

  echo "[SUCCESS] 证书签发完成！"
  echo "私钥: ${KEY_PATH}"
  echo "证书: ${CERT_PATH}"
}

# ========== 尝试 ECC，失败切换 RSA ==========
if ! issue_cert "ec-256" "zerossl"; then
  echo "[WARN] ECC 签发失败，尝试 RSA ..."
  issue_cert "4096" "zerossl" || issue_cert "4096" "letsencrypt"
fi

# ========== 安装 cron ==========
echo "[INFO] 安装自动续签任务..."
/root/.acme.sh/acme.sh --install-cronjob >>"$LOG_PATH" 2>&1

echo "[DONE] 任务完成！日志: $LOG_PATH"
