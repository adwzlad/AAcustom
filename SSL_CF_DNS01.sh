#!/bin/bash
# ========================================
# 一键签发 主域名 + *.域名 通配符证书（Cloudflare DNS）
# 使用 acme.sh + ECC，证书保存到 /root/cert
# 文件名为 private.key 与 public.crt
# ========================================

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] 请使用 root 权限执行：sudo -i"
  exit 1
fi

read -p "请输入 Cloudflare API Token: " CF_Token
read -p "请输入要签发的主域名 (例如 a.com): " DOMAIN

CERT_DIR="/root/cert"
mkdir -p "${CERT_DIR}"

KEY_PATH="${CERT_DIR}/private.key"
CERT_PATH="${CERT_DIR}/public.crt"

# 检查 acme.sh 是否存在
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
  echo "[INFO] acme.sh 未安装，正在自动安装..."
  curl https://get.acme.sh | sh
fi

# 加载 acme.sh 环境变量
export PATH=$PATH:/root/.acme.sh
source /root/.bashrc 2>/dev/null || true

# 导出 Cloudflare API Token
export CF_Token="$CF_Token"

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
