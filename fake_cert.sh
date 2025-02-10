#!/bin/bash

# 提示用户输入证书保存路径
read -p "请输入证书保存路径（默认：/root/cret/fake）: " CERT_PATH
CERT_PATH=${CERT_PATH:-/root/cret/fake}

# 提示用户输入伪造的域名
read -p "请输入伪造的域名（例如 fake.example.com）: " FAKE_DOMAIN
if [ -z "$FAKE_DOMAIN" ]; then
    echo "❌ 域名不能为空！"
    exit 1
fi

# 自动创建证书存储目录（如果不存在）
mkdir -p "$CERT_PATH"

# 生成伪造的自签名 TLS 证书（15 年有效期）
openssl req -newkey rsa:4096 -nodes -keyout "$CERT_PATH/fake.key" -x509 -days 5475 -out "$CERT_PATH/fake.crt" -subj "/CN=$FAKE_DOMAIN"

# 赋予证书文件适当的权限（防止非 root 访问）
chmod 600 "$CERT_PATH/fake.key"
chmod 644 "$CERT_PATH/fake.crt"

# 输出成功信息
echo "✅ 伪造证书已生成:"
echo "🔑 私钥: $CERT_PATH/fake.key"
echo "📜 证书: $CERT_PATH/fake.crt"
