#!/bin/bash
# ========================================
# 一键签发 主域名 + *.域名 通配符证书（Cloudflare DNS）
# 使用 acme.sh + ECC，证书保存到 /root/cert
# 文件名为 private.key 与 public.crt
# 自动检测并选择已有 Cloudflare API Token
# 自动注册 ZeroSSL 账户邮箱（或切换到 Let's Encrypt）
# ========================================

set -e

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] 请使用 root 权限执行：sudo -i"
  exit 1
fi

# 检查是否已有 CF_Token
if [ -n "$CF_Token" ]; then
  echo "[INFO] 检测到已存在的 Cloudflare API Token: ${CF_Token:0:10}******"
  read -p "是否使用此 Token？(Y/n): " use_old
  case "$use_old" in
    [nN]*) read -p "请输入新的 Cloudflare API Token: " CF_Token ;;
    *) echo "[INFO] 继续使用现有 Token" ;;
  esac
else
  read -p "请输入 Cloudflare API Token: " CF_Token
fi

# 输入主域名
read -p "请输入要签发的主域名 (例如 a.com): " DOMAIN

CERT_DIR="/root/cert"
mkdir -p "${CERT_DIR}"

KEY_PATH="${CERT_DIR}/private.key"
CERT_PATH="${CERT_DIR}/public.crt"

# 检查 acme.sh 是否存在
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
  echo "[INFO] acme.sh 未安装，正在自动安装..."
  curl https://get.acme.sh | sh
  source /root/.bashrc 2>/dev/null || true
fi

# 加载 acme.sh 环境变量
export PATH=$PATH:/root/.acme.sh
source /root/.bashrc 2>/dev/null || true

# 导出 Cloudflare Token 环境变量
export CF_Token="$CF_Token"

# 检查当前 CA
CA=$(/root/.acme.sh/acme.sh --show-ca 2>/dev/null || true)

if [[ "$CA" == *"zerossl"* ]]; then
  echo "[INFO] 当前使用的 CA 是 ZeroSSL。"
  read -p "请输入用于注册 ZeroSSL 账户的邮箱 (例如 admin@${DOMAIN}): " EMAIL
  echo "[INFO] 正在注册 ZeroSSL 账户..."
  /root/.acme.sh/acme.sh --register-account -m "$EMAIL" || true
else
  echo "[INFO] 当前使用的 CA 是 Let's Encrypt。"
  read -p "是否要切换到 ZeroSSL？(y/N): " to_zero
  if [[ "$to_zero" =~ ^[yY]$ ]]; then
    /root/.acme.sh/acme.sh --set-default-ca --server zerossl
    read -p "请输入用于注册 ZeroSSL 账户的邮箱: " EMAIL
    /root/.acme.sh/acme.sh --register-account -m "$EMAIL" || true
  fi
fi

echo "[INFO] 开始签发证书 ${DOMAIN} 和 *.${DOMAIN} ..."
/root/.acme.sh/acme.sh --issue --dns dns_cf -d "${DOMAIN}" -d "*.${DOMAIN}" --keylength ec-256

echo "[INFO] 安装证书到 ${CERT_DIR} ..."
/root/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" \
  --key-file "${KEY_PATH}" \
  --fullchain-file "${CERT_PATH}" \
  --ecc

chmod 600 "${KEY_PATH}" 2>/dev/null
chmod 644 "${CERT_PATH}" 2>/dev/null

echo "[SUCCESS] 主域名与通配符证书签发完成！"
echo "私钥路径: ${KEY_PATH}"
echo "证书路径: ${CERT_PATH}"

echo "[INFO] 安装自动续签任务..."
/root/.acme.sh/acme.sh --install-cronjob

echo "[DONE] 全部任务完成！证书将会自动续签。"
