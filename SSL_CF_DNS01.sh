#!/bin/bash
# ========================================
# 一键签发 *.域名 通配符证书（Cloudflare DNS）
# 证书安装到 /root/cert
# 支持远程拉取执行 + 自动续签
# 只签发 *.域名
# ========================================

# 确保以 root 执行
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] 请使用 sudo 或 root 执行此脚本" 
   exit 1
fi

# --------- 交互式输入 ---------
read -p "请输入 Cloudflare API Token: " CF_Token
read -p "请输入要签发的主域名 (例如 787612.xyz): " DOMAIN

# 设置证书保存目录
CERT_DIR="/root/cert"
mkdir -p "${CERT_DIR}"

KEY_PATH="${CERT_DIR}/${DOMAIN}.key"
CERT_PATH="${CERT_DIR}/${DOMAIN}.crt"
# -------------------------------

# 安装 acme.sh（如果未安装）
if ! command -v acme.sh &>/dev/null; then
    echo "[INFO] acme.sh 未安装，自动安装中..."
    curl https://get.acme.sh | sh
    source /root/.bashrc
fi

# 将 CF_Token 写入 acme.sh 环境，保证续签可用
ACME_ENV_FILE="/root/.acme.sh/account.conf"
grep -q '^CF_Token=' "$ACME_ENV_FILE" 2>/dev/null || echo "export CF_Token=\"$CF_Token\"" >> "$ACME_ENV_FILE"

export CF_Token

echo "[INFO] 开始签发通配符证书 *.${DOMAIN} ..."
acme.sh --issue --dns dns_cf -d "*.${DOMAIN}" --keylength ec-256

echo "[INFO] 安装证书到 ${CERT_DIR} ..."
acme.sh --install-cert -d "*.${DOMAIN}" \
--key-file "${KEY_PATH}" \
--fullchain-file "${CERT_PATH}" \
--ecc

chmod 600 "${KEY_PATH}"
chmod 644 "${CERT_PATH}"

echo "[SUCCESS] 通配符证书已安装完成！"
echo "私钥路径: ${KEY_PATH}"
echo "证书路径: ${CERT_PATH}"

# 安装 cron 自动续签任务
echo "[INFO] 安装 cron 自动续签任务..."
/root/.acme.sh/acme.sh --install-cronjob
