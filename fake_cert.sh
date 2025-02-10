#!/bin/bash

# 设置默认证书路径
read -p "请输入证书保存路径（默认：/root/cret/fake）: " CERT_PATH
CERT_PATH=${CERT_PATH:-/root/cret/fake}

# 设置伪造的域名
read -p "请输入伪造的域名（例如 fake.example.com）: " FAKE_DOMAIN
if [ -z "$FAKE_DOMAIN" ]; then
    echo "❌ 域名不能为空！"
    exit 1
fi

# 创建目标目录
mkdir -p "$CERT_PATH"

# 生成伪造的自签名证书
openssl req -newkey rsa:4096 -nodes -keyout "$CERT_PATH/fake.key" -x509 -days 5475 -out "$CERT_PATH/fake.crt" -subj "/CN=$FAKE_DOMAIN
