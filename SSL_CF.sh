#!/bin/bash

# ============================================================
# Cloudflare DNS + acme.sh SSL Certificate Manager
#
# 功能：
#
# 1. 主域名 + 通配符
#    example.com
#    *.example.com
#
# 2. 多个指定域名
#    node.example.com
#    api.example.com
#    www.example.net
#
# 特性：
# - Cloudflare DNS-01
# - Let's Encrypt
# - ECC-256 优先
# - ECC-256 失败自动 RSA-4096
# - 多域名 SAN 证书
# - 自动生成 ACME 邮箱
# - 申请过程实时显示
# - 同时保存完整日志
# - 自动安装证书
# - 自动续签
# - 自动更新证书文件
#
# 配置：
# /root/.acme-auto/config
#
# 证书：
# /root/cert/private.key
# /root/cert/public.crt
#
# 日志：
# /root/cert/acme.log
#
# ============================================================

set -o pipefail


# ============================================================
# 基础配置
# ============================================================

CONF_DIR="/root/.acme-auto"
CONF_FILE="$CONF_DIR/config"

CERT_DIR="/root/cert"

LOG_FILE="$CERT_DIR/acme.log"

ACME_HOME="/root/.acme.sh"

ACME_BIN="$ACME_HOME/acme.sh"


# ============================================================
# Root 检查
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo
    echo "[ERROR] 必须使用 root 用户运行此脚本。"
    echo
    exit 1
fi


# ============================================================
# 创建目录
# ============================================================

mkdir -p "$CONF_DIR"
mkdir -p "$CERT_DIR"

chmod 700 "$CONF_DIR"
chmod 700 "$CERT_DIR"


# ============================================================
# 输出函数
# ============================================================

log() {
    echo "$1" | tee -a "$LOG_FILE"
}


info() {
    log "[INFO] $1"
}


ok() {
    log "[OK] $1"
}


warn() {
    log "[WARN] $1"
}


error() {
    log "[ERROR] $1"
}


# ============================================================
# 域名检查
# ============================================================

validate_domain() {

    local domain="$1"

    if [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
        return 0
    fi

    return 1
}


# ============================================================
# 生成随机 ACME 邮箱
#
# 使用申请域名作为邮箱域名。
#
# 例如：
# example.com
#
# 自动生成：
# acme-7f3a91c2@example.com
#
# 仅用于 ACME 账户注册。
# ============================================================

generate_acme_email() {

    local RANDOM_ID

    RANDOM_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"

    echo "acme-${RANDOM_ID}@${DOMAIN}"
}


# ============================================================
# 新建配置
# ============================================================

configure_new() {

    echo
    echo "============================================================"
    echo "             Cloudflare SSL 证书配置"
    echo "============================================================"
    echo

    echo "请输入 Cloudflare API Token。"
    echo
    echo "Token 至少需要具有："
    echo "  Zone - DNS - Edit"
    echo
    echo "Token 不会显示在屏幕上。"
    echo

    read -r -s -p "Cloudflare API Token: " CF_TOKEN

    echo

    if [ -z "$CF_TOKEN" ]; then
        echo
        error "Cloudflare API Token 不能为空。"
        exit 1
    fi


    # ========================================================
    # 申请模式
    # ========================================================

    echo
    echo "============================================================"
    echo "                    选择证书模式"
    echo "============================================================"
    echo

    echo "  [1] 主域名 + 通配符"
    echo
    echo "      例如输入："
    echo "        example.com"
    echo
    echo "      自动申请："
    echo "        example.com"
    echo "        *.example.com"
    echo
    echo "      适合需要覆盖整个主域名所有子域名的情况。"
    echo


    echo "  [2] 多个指定域名"
    echo
    echo "      只申请你明确指定的域名。"
    echo "      不会自动增加通配符。"
    echo
    echo "      例如："
    echo "        node.example.com"
    echo "        api.example.com"
    echo "        www.example.net"
    echo
    echo "      多个域名会放入同一张 SAN 证书。"
    echo


    echo "============================================================"
    echo

    while true; do

        read -r -p "请选择 [1/2]: " CERT_MODE

        case "$CERT_MODE" in

            1)

                # ==================================================
                # 模式 1
                # ==================================================

                echo
                echo "------------------------------------------------------------"
                echo "模式 1：主域名 + 通配符"
                echo "------------------------------------------------------------"
                echo

                read -r -p "请输入主域名，例如 example.com: " DOMAIN

                # 去掉首尾空格
                DOMAIN="$(echo "$DOMAIN" | xargs)"

                if ! validate_domain "$DOMAIN"; then

                    echo
                    error "域名格式不正确：$DOMAIN"
                    echo

                    continue
                fi


                DOMAIN_LIST=(
                    "$DOMAIN"
                    "*.$DOMAIN"
                )

                break
                ;;


            2)

                # ==================================================
                # 模式 2
                # ==================================================

                echo
                echo "------------------------------------------------------------"
                echo "模式 2：多个指定域名"
                echo "------------------------------------------------------------"
                echo

                echo "每行输入一个域名。"
                echo "输入空行结束。"
                echo
                echo "例如："
                echo "  node.example.com"
                echo "  api.example.com"
                echo "  www.example.net"
                echo

                DOMAIN_LIST=()


                while true; do

                    read -r -p "域名: " INPUT_DOMAIN

                    INPUT_DOMAIN="$(echo "$INPUT_DOMAIN" | xargs)"


                    # 空行结束
                    if [ -z "$INPUT_DOMAIN" ]; then
                        break
                    fi


                    # ==================================================
                    # 域名检查
                    # ==================================================

                    if ! validate_domain "$INPUT_DOMAIN"; then

                        warn "域名格式不正确，跳过：$INPUT_DOMAIN"

                        continue
                    fi


                    # ==================================================
                    # 重复检查
                    # ==================================================

                    DUPLICATE=0

                    for EXISTING_DOMAIN in "${DOMAIN_LIST[@]}"; do

                        if [ "$EXISTING_DOMAIN" = "$INPUT_DOMAIN" ]; then

                            DUPLICATE=1

                            break
                        fi

                    done


                    if [ "$DUPLICATE" -eq 1 ]; then

                        warn "域名重复，跳过：$INPUT_DOMAIN"

                        continue
                    fi


                    DOMAIN_LIST+=("$INPUT_DOMAIN")

                    ok "已添加：$INPUT_DOMAIN"

                done


                if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then

                    error "至少需要输入一个有效域名。"

                    continue
                fi


                # 第一个域名作为 acme.sh 的主证书标识
                DOMAIN="${DOMAIN_LIST[0]}"

                break
                ;;


            *)

                error "请选择 1 或 2。"

                ;;

        esac

    done


    # ========================================================
    # 自动生成邮箱
    # ========================================================

    ACME_EMAIL="$(generate_acme_email)"


    # ========================================================
    # 保存域名
    # ========================================================

    DOMAINS=""

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do

        if [ -z "$DOMAINS" ]; then
            DOMAINS="$CERT_DOMAIN"
        else
            DOMAINS="$DOMAINS $CERT_DOMAIN"
        fi

    done


    # ========================================================
    # 保存配置
    # ========================================================

    cat > "$CONF_FILE" <<EOF
CF_TOKEN='$CF_TOKEN'
CERT_MODE='$CERT_MODE'
DOMAIN='$DOMAIN'
DOMAINS='$DOMAINS'
ACME_EMAIL='$ACME_EMAIL'
EOF

    chmod 600 "$CONF_FILE"


    # ========================================================
    # 显示配置结果
    # ========================================================

    echo
    echo "============================================================"
    echo "                    配置完成"
    echo "============================================================"
    echo

    echo "证书模式："

    if [ "$CERT_MODE" = "1" ]; then
        echo "  主域名 + 通配符"
    else
        echo "  多个指定域名"
    fi

    echo

    echo "证书域名："

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
        echo "  - $CERT_DOMAIN"
    done

    echo

    echo "ACME 注册邮箱："
    echo "  $ACME_EMAIL"

    echo
    echo "配置文件："
    echo "  $CONF_FILE"

    echo
}


# ============================================================
# 读取配置
# ============================================================

if [ -f "$CONF_FILE" ]; then

    echo
    echo "============================================================"
    echo "                  读取已有配置"
    echo "============================================================"
    echo

    source "$CONF_FILE"

    if [ -z "${CF_TOKEN:-}" ]; then
        error "配置文件中没有 CF_TOKEN。"
        exit 1
    fi

    if [ -z "${CERT_MODE:-}" ]; then
        error "配置文件中没有 CERT_MODE。"
        exit 1
    fi

    if [ -z "${DOMAIN:-}" ]; then
        error "配置文件中没有 DOMAIN。"
        exit 1
    fi

    if [ -z "${DOMAINS:-}" ]; then
        error "配置文件中没有 DOMAINS。"
        exit 1
    fi

    if [ -z "${ACME_EMAIL:-}" ]; then
        error "配置文件中没有 ACME_EMAIL。"
        exit 1
    fi

else

    configure_new

    source "$CONF_FILE"

fi


# ============================================================
# 构建域名数组
# ============================================================

DOMAIN_LIST=()

read -r -a DOMAIN_LIST <<< "$DOMAINS"


if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then

    error "没有可用的证书域名。"

    exit 1
fi


# ============================================================
# Cloudflare API Token
# ============================================================

export CF_Token="$CF_TOKEN"


# ============================================================
# 显示本次任务
# ============================================================

echo
echo "============================================================"
echo "                  SSL 证书申请任务"
echo "============================================================"
echo

echo "申请模式："

if [ "$CERT_MODE" = "1" ]; then
    echo "  主域名 + 通配符"
else
    echo "  多个指定域名"
fi

echo

echo "申请域名："

for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
    echo "  - $CERT_DOMAIN"
done

echo

echo "ACME 邮箱："
echo "  $ACME_EMAIL"

echo

echo "证书目录："
echo "  $CERT_DIR"

echo

echo "日志文件："
echo "  $LOG_FILE"

echo
echo "============================================================"
echo


# ============================================================
# 检查 curl
# ============================================================

if ! command -v curl >/dev/null 2>&1; then

    info "系统未安装 curl。"

    if command -v apt-get >/dev/null 2>&1; then

        info "正在安装 curl..."

        apt-get update

        apt-get install -y curl

    else

        error "系统没有 apt-get，无法自动安装 curl。"

        exit 1
    fi

fi


# ============================================================
# 安装 acme.sh
# ============================================================

if [ ! -f "$ACME_BIN" ]; then

    echo
    echo "============================================================"
    echo "                  安装 acme.sh"
    echo "============================================================"
    echo

    info "未检测到 acme.sh。"
    info "开始安装..."
    echo


    if curl https://get.acme.sh | sh 2>&1 | tee -a "$LOG_FILE"; then

        echo
        ok "acme.sh 安装命令执行完成。"

    else

        echo
        error "acme.sh 安装失败。"

        exit 1
    fi

fi


# ============================================================
# 检查 acme.sh
# ============================================================

if [ ! -f "$ACME_BIN" ]; then

    error "找不到 acme.sh：$ACME_BIN"

    exit 1
fi


export PATH="$ACME_HOME:$PATH"


echo
echo "============================================================"
echo "                  acme.sh 信息"
echo "============================================================"
echo

"$ACME_BIN" --version 2>&1 | tee -a "$LOG_FILE"

echo


# ============================================================
# Let's Encrypt ACME 账户
# ============================================================

echo
echo "============================================================"
echo "              Let's Encrypt ACME 账户"
echo "============================================================"
echo

info "使用自动生成的 ACME 邮箱：$ACME_EMAIL"
echo
info "开始注册/检查 Let's Encrypt ACME 账户..."
echo


"$ACME_BIN" \
    --register-account \
    -m "$ACME_EMAIL" \
    --server letsencrypt \
    2>&1 | tee -a "$LOG_FILE"

REGISTER_RESULT=${PIPESTATUS[0]}


if [ "$REGISTER_RESULT" -eq 0 ]; then

    echo
    ok "Let's Encrypt ACME 账户准备完成。"

else

    echo
    warn "ACME 账户命令返回代码：$REGISTER_RESULT"
    warn "如果账户已经存在，可以继续尝试申请证书。"

fi


# ============================================================
# 构建 acme.sh 域名参数
# ============================================================

DOMAIN_ARGS=()

for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do

    DOMAIN_ARGS+=(
        -d "$CERT_DOMAIN"
    )

done


# ============================================================
# 证书申请函数
# ============================================================

issue_certificate() {

    local KEY_LENGTH="$1"

    echo
    echo "============================================================"
    echo "                 开始申请证书"
    echo "============================================================"
    echo

    echo "密钥类型："
    echo "  $KEY_LENGTH"

    echo

    echo "DNS 验证："
    echo "  Cloudflare DNS-01"

    echo

    echo "证书 CA："
    echo "  Let's Encrypt"

    echo

    echo "DNS 等待时间："
    echo "  60 秒"

    echo

    echo "本次证书域名："

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
        echo "  - $CERT_DOMAIN"
    done

    echo

    echo "------------------------------------------------------------"
    echo "                  acme.sh 实时输出"
    echo "------------------------------------------------------------"
    echo


    "$ACME_BIN" \
        --issue \
        --dns dns_cf \
        "${DOMAIN_ARGS[@]}" \
        --keylength "$KEY_LENGTH" \
        --server letsencrypt \
        --dnssleep 60 \
        2>&1 | tee -a "$LOG_FILE"

    local RESULT=${PIPESTATUS[0]}


    echo
    echo "------------------------------------------------------------"


    if [ "$RESULT" -eq 0 ]; then

        echo "[OK] $KEY_LENGTH 证书申请成功。"

    else

        echo "[ERROR] $KEY_LENGTH 证书申请失败。"
        echo "[ERROR] 返回代码：$RESULT"

    fi

    echo "------------------------------------------------------------"
    echo

    return "$RESULT"
}


# ============================================================
# ECC-256 优先
# ============================================================

echo
echo "============================================================"
echo "              第一阶段：ECC-256"
echo "============================================================"
echo


CERT_TYPE=""


if issue_certificate "ec-256"; then

    CERT_TYPE="ECC"

    echo
    echo "============================================================"
    echo "                ECC-256 申请成功"
    echo "============================================================"
    echo

else

    echo
    echo "============================================================"
    echo "                ECC-256 申请失败"
    echo "============================================================"
    echo

    warn "ECC-256 申请失败。"
    warn "自动切换 RSA-4096。"

    echo
    echo "============================================================"
    echo "              第二阶段：RSA-4096"
    echo "============================================================"
    echo


    if issue_certificate "4096"; then

        CERT_TYPE="RSA"

        echo
        echo "============================================================"
        echo "                RSA-4096 申请成功"
        echo "============================================================"
        echo

    else

        echo
        echo "============================================================"
        echo "                 ❌ 证书申请失败"
        echo "============================================================"
        echo

        error "ECC-256 和 RSA-4096 均申请失败。"
        error "详细日志：$LOG_FILE"

        exit 1
    fi

fi


# ============================================================
# 安装证书
# ============================================================

echo
echo "============================================================"
echo "                    安装证书"
echo "============================================================"
echo

echo "证书类型："
echo "  $CERT_TYPE"

echo

echo "证书安装位置："
echo "  $CERT_DIR/private.key"
echo "  $CERT_DIR/public.crt"

echo


if [ "$CERT_TYPE" = "ECC" ]; then

    "$ACME_BIN" \
        --install-cert \
        -d "$DOMAIN" \
        --ecc \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/public.crt" \
        2>&1 | tee -a "$LOG_FILE"

else

    "$ACME_BIN" \
        --install-cert \
        -d "$DOMAIN" \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/public.crt" \
        2>&1 | tee -a "$LOG_FILE"

fi


INSTALL_RESULT=${PIPESTATUS[0]}


if [ "$INSTALL_RESULT" -ne 0 ]; then

    echo
    error "证书安装失败。"
    error "返回代码：$INSTALL_RESULT"
    error "详细日志：$LOG_FILE"

    exit 1
fi


echo
ok "证书安装成功。"


# ============================================================
# 设置权限
# ============================================================

echo
info "设置证书文件权限..."

chmod 600 "$CERT_DIR/private.key"
chmod 644 "$CERT_DIR/public.crt"

ok "证书权限设置完成。"


# ============================================================
# 安装自动续期任务
# ============================================================

echo
echo "============================================================"
echo "                    自动续期"
echo "============================================================"
echo

info "正在安装 acme.sh 自动续期任务..."
echo


"$ACME_BIN" \
    --install-cronjob \
    2>&1 | tee -a "$LOG_FILE"

CRON_RESULT=${PIPESTATUS[0]}


if [ "$CRON_RESULT" -eq 0 ]; then

    echo
    ok "自动续期任务安装成功。"

else

    echo
    warn "自动续期任务安装返回代码：$CRON_RESULT"
    warn "请检查：$LOG_FILE"

fi


# ============================================================
# 显示证书文件
# ============================================================

echo
echo "============================================================"
echo "                  检查证书文件"
echo "============================================================"
echo


if [ -f "$CERT_DIR/private.key" ]; then

    ok "私钥：$CERT_DIR/private.key"

else

    error "私钥不存在：$CERT_DIR/private.key"

fi


if [ -f "$CERT_DIR/public.crt" ]; then

    ok "证书：$CERT_DIR/public.crt"

else

    error "证书不存在：$CERT_DIR/public.crt"

fi


# ============================================================
# OpenSSL 证书信息
# ============================================================

if command -v openssl >/dev/null 2>&1 &&
   [ -f "$CERT_DIR/public.crt" ]; then

    echo
    echo "============================================================"
    echo "                  证书详细信息"
    echo "============================================================"
    echo


    openssl x509 \
        -in "$CERT_DIR/public.crt" \
        -noout \
        -subject \
        -issuer \
        -serial \
        -dates \
        -ext subjectAltName \
        2>&1 | tee -a "$LOG_FILE"

fi


# ============================================================
# acme.sh 当前证书列表
# ============================================================

echo
echo "============================================================"
echo "                acme.sh 当前证书"
echo "============================================================"
echo


"$ACME_BIN" --list 2>&1 | tee -a "$LOG_FILE" || true


# ============================================================
# 最终结果
# ============================================================

echo
echo
echo "============================================================"
echo "                  ✅ SSL 配置完成"
echo "============================================================"
echo

echo "证书模式："

if [ "$CERT_MODE" = "1" ]; then
    echo "  主域名 + 通配符"
else
    echo "  多个指定域名"
fi

echo

echo "证书域名："

for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
    echo "  - $CERT_DOMAIN"
done

echo

echo "证书类型："
echo "  $CERT_TYPE"

echo

echo "证书："
echo "  $CERT_DIR/public.crt"

echo

echo "私钥："
echo "  $CERT_DIR/private.key"

echo

echo "配置："
echo "  $CONF_FILE"

echo

echo "日志："
echo "  $LOG_FILE"

echo

echo "自动续期："
echo "  已启用 acme.sh Cron"

echo
echo "============================================================"
echo "          证书到期前 acme.sh 会自动进行续签"
echo "============================================================"
echo
```
