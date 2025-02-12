#!/bin/bash

# 提示用户输入证书保存路径
read -p "请输入证书保存路径（默认：/root/cert/fake）: " CERT_PATH
CERT_PATH=${CERT_PATH:-/root/cert/fake}

# 提示用户输入伪造的域名
read -p "请输入伪造的域名（例如 fake.example.com）: " FAKE_DOMAIN
if [ -z "$FAKE_DOMAIN" ]; then
    echo "❌ 域名不能为空！"
    exit 1
fi

# 提示用户输入证书有效期（1 - 15 年）
while true; do
    read -p "请输入证书有效期（1 - 15 年）: " VALID_YEARS
    if [[ "$VALID_YEARS" =~ ^[1-9]$|^1[0-5]$ ]]; then
        break
    else
        echo "❌ 输入无效，请输入 1 至 15 之间的整数。"
    fi
done

# 将年转换为天
VALID_DAYS=$((VALID_YEARS * 365))

# 自动创建证书存储目录（如果不存在）
mkdir -p "$CERT_PATH"

# 生成伪造的自签名 TLS 证书（指定有效期）
openssl req -newkey rsa:4096 -nodes -keyout "$CERT_PATH/fake.key" -x509 -days "$VALID_DAYS" -out "$CERT_PATH/fake.crt" -subj "/CN=$FAKE_DOMAIN"

# 赋予证书文件适当的权限（防止非 root 访问）
chmod 600 "$CERT_PATH/fake.key"
chmod 644 "$CERT_PATH/fake.crt"

# 输出成功信息
echo "✅ 伪造证书已生成:"
echo "🔑 私钥: $CERT_PATH/fake.key"
echo "📜 证书: $CERT_PATH/fake.crt"
echo "📅 有效期: $VALID_YEARS 年"
