#!/bin/bash
# ========================================
# 一键签发 *.域名 通配符证书（Cloudflare DNS）
# 证书安装到 /root/cert
# 自动检测 acme.sh 路径并支持首次安装
# ========================================

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] 请使用 root 权限执行：sudo -i"
  exit 1
fi

read -p "请输入 Cloudflare API Token: " CF_Token
read -p "请输入要签发的主域名 (例如 a.com): " DOMAIN

CERT_DIR="/root/cert"
mkdir -p "${CERT_DIR}"

KEY_PATH="${CERT_DIR}/${DOMAIN}.key"
CERT_PATH="${CERT_DIR}/${DOMAIN}.crt"

# 确保 acme.sh 可用
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
  echo "[INFO] acme.sh 未安装，正在安装..."
  curl https://get.acme.sh | sh
fi

# 加载 acme.sh 环境
export PATH=$PATH:/root/.acme.sh
source /root/.bashrc 2>/dev/null || true

export CF_Token="$CF_Token"

echo "[INFO] 开始签发通配符证书 *.${DOMAIN} ..."
/root/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${DOMAIN}" --keylength ec-256

echo "[INFO] 安装证书到 ${CERT_DIR} ..."
/root/.acme.sh/acme.sh --install-cert -d "*.${DOMAIN}" \
--key-file "${KEY_PATH}" \
--fullchain-file "${CERT_PATH}" \
--ecc

chmod 600 "${KEY_PATH}" 2>/dev/null
chmod 644 "${CERT_PATH}" 2>/dev/null

echo "[SUCCESS] 通配符证书签发完成！"
echo "私钥路径: ${KEY_PATH}"
echo "证书路径: ${CERT_PATH}"

echo "[INFO] 配置自动续签任务..."
/root/.acme.sh/acme.sh --install-cronjob
