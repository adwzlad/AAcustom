#!/bin/bash

# ==================================================
# Cloudflare DNS + acme.sh
#
# 支持：
# 1. 主域名 + *.通配符（原有模式）
# 2. 多个指定域名（新增模式）
#
# 原有功能：
# - Cloudflare DNS-01
# - Let's Encrypt
# - 自动缓存参数
# - ECC-256 优先
# - ECC 失败自动 RSA-4096
# - 证书安装到 /root/cert/
# - 自动续期
# - 自动更新证书文件
# - 旧版配置兼容
#
# ==================================================

set -e

# ---------- root 检查 ----------

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 执行"
    exit 1
fi


# ---------- 配置文件 ----------

CONF_DIR="/root/.acme-auto"
CONF_FILE="$CONF_DIR/config"

CERT_DIR="/root/cert"
LOG_FILE="$CERT_DIR/acme.log"

mkdir -p "$CONF_DIR" "$CERT_DIR"


# ==================================================
# 域名格式检查
# ==================================================

validate_domain() {

    local domain="$1"

    # 允许普通域名
    if [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
        return 0
    fi

    return 1
}


# ==================================================
# 新建配置
# ==================================================

configure_new() {

    echo
    echo "===================================="
    echo " Cloudflare SSL 证书配置"
    echo "===================================="
    echo

    read -p "请输入 Cloudflare API Token: " CF_Token

    if [ -z "$CF_Token" ]; then
        echo "[ERROR] Cloudflare API Token 不能为空"
        exit 1
    fi


    echo
    echo "请选择证书申请模式："
    echo
    echo "  1. 主域名 + 通配符（原有模式）"
    echo "  2. 指定多个域名（新增模式）"
    echo

    while true; do

        read -p "请选择 [1-2]: " CERT_MODE

        case "$CERT_MODE" in

            # ==================================================
            # 模式 1
            # 原来的 DOMAIN + *.DOMAIN
            # ==================================================

            1)

                echo
                read -p "请输入主域名 (如 example.com): " DOMAIN

                if ! validate_domain "$DOMAIN"; then
                    echo "[ERROR] 域名格式不正确：$DOMAIN"
                    continue
                fi

                # 原有行为
                DOMAINS="$DOMAIN *.$DOMAIN"

                break
                ;;


            # ==================================================
            # 模式 2
            # 多个指定域名
            # ==================================================

            2)

                echo
                echo "请输入需要申请的域名。"
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

                    read -p "域名: " INPUT_DOMAIN

                    # 空行结束
                    if [ -z "$INPUT_DOMAIN" ]; then
                        break
                    fi


                    if ! validate_domain "$INPUT_DOMAIN"; then
                        echo "[WARN] 域名格式不正确，跳过：$INPUT_DOMAIN"
                        continue
                    fi


                    # 检查重复
                    DUPLICATE=0

                    for EXISTING_DOMAIN in "${DOMAIN_LIST[@]}"; do

                        if [ "$EXISTING_DOMAIN" = "$INPUT_DOMAIN" ]; then
                            DUPLICATE=1
                            break
                        fi

                    done


                    if [ "$DUPLICATE" -eq 1 ]; then
                        echo "[WARN] 域名已经存在，跳过：$INPUT_DOMAIN"
                        continue
                    fi


                    DOMAIN_LIST+=("$INPUT_DOMAIN")

                    echo "[OK] 已添加：$INPUT_DOMAIN"

                done


                if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then
                    echo "[ERROR] 至少需要输入一个域名"
                    continue
                fi


                # 第一个域名作为 acme.sh 证书主标识
                DOMAIN="${DOMAIN_LIST[0]}"

                # 保存为空格分隔
                DOMAINS="${DOMAIN_LIST[*]}"

                break
                ;;


            *)
                echo "[ERROR] 请输入 1 或 2"
                ;;

        esac

    done


    echo
    read -p "请输入邮箱 (用于 LE 注册): " ACME_EMAIL

    if [ -z "$ACME_EMAIL" ]; then
        echo "[ERROR] 邮箱不能为空"
        exit 1
    fi


    # ==================================================
    # 保存配置
    # ==================================================

    cat > "$CONF_FILE" <<EOF
export CF_Token="$CF_Token"
export DOMAIN="$DOMAIN"
export DOMAINS="$DOMAINS"
export CERT_MODE="$CERT_MODE"
export ACME_EMAIL="$ACME_EMAIL"
EOF

    chmod 600 "$CONF_FILE"

    echo
    echo "[INFO] 配置已保存：$CONF_FILE"
}


# ==================================================
# 读取配置
# ==================================================

if [ -f "$CONF_FILE" ]; then

    source "$CONF_FILE"

    echo
    echo "[INFO] 已读取缓存配置：$CONF_FILE"
    echo


    # ==================================================
    # 兼容原来的旧配置
    #
    # 原脚本只有：
    #
    # CF_Token
    # DOMAIN
    # ACME_EMAIL
    #
    # 没有 CERT_MODE / DOMAINS
    #
    # 所以自动按原模式处理：
    #
    # DOMAIN
    # *.DOMAIN
    # ==================================================

    if [ -z "${CERT_MODE:-}" ]; then

        CERT_MODE="1"

        if [ -n "${DOMAIN:-}" ]; then
            DOMAINS="$DOMAIN *.$DOMAIN"
        fi

        echo "[INFO] 检测到旧版配置"
        echo "[INFO] 自动使用原有模式："
        echo "       $DOMAIN"
        echo "       *.$DOMAIN"
        echo

    fi


else

    # ==================================================
    # 新主机
    # ==================================================

    configure_new

fi


# ==================================================
# 重新读取配置
# ==================================================

source "$CONF_FILE"


# ==================================================
# 构建域名数组
# ==================================================

DOMAIN_LIST=()


if [ "$CERT_MODE" = "1" ]; then

    # ==================================================
    # 原模式
    #
    # example.com
    # *.example.com
    # ==================================================

    if [ -z "${DOMAIN:-}" ]; then
        echo "[ERROR] DOMAIN 未配置"
        exit 1
    fi

    DOMAIN_LIST=(
        "$DOMAIN"
        "*.$DOMAIN"
    )


else

    # ==================================================
    # 新模式
    #
    # 只申请指定域名
    # ==================================================

    if [ -z "${DOMAINS:-}" ]; then
        echo "[ERROR] DOMAINS 未配置"
        exit 1
    fi

    read -r -a DOMAIN_LIST <<< "$DOMAINS"


    if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then
        echo "[ERROR] 没有可用域名"
        exit 1
    fi

fi


# ==================================================
# 显示本次证书域名
# ==================================================

echo
echo "===================================="
echo " 本次证书申请域名"
echo "===================================="

for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
    echo "  $CERT_DOMAIN"
done

echo "===================================="
echo


# ==================================================
# 安装 acme.sh
# ==================================================

if [ ! -f /root/.acme.sh/acme.sh ]; then

    echo "[INFO] 未检测到 acme.sh"
    echo "[INFO] 开始安装..."

    curl https://get.acme.sh | sh

fi


export PATH="$PATH:/root/.acme.sh"


# ==================================================
# 检查 acme.sh
# ==================================================

if [ ! -f /root/.acme.sh/acme.sh ]; then

    echo "[ERROR] acme.sh 安装失败"
    exit 1

fi


# ==================================================
# Let's Encrypt 注册
# ==================================================

/root/.acme.sh/acme.sh \
    --register-account \
    -m "$ACME_EMAIL" \
    --server letsencrypt \
    >> "$LOG_FILE" 2>&1 || true


# ==================================================
# 签发证书
# ==================================================

issue() {

    local KEYLEN="$1"

    echo
    echo "===================================="
    echo " 开始申请证书"
    echo "===================================="
    echo "[INFO] Key：$KEYLEN"
    echo

    # ------------------------------------------------
    # 构造域名参数
    # ------------------------------------------------

    local DOMAIN_ARGS=()

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do

        echo "[INFO] 域名：$CERT_DOMAIN"

        DOMAIN_ARGS+=(
            -d "$CERT_DOMAIN"
        )

    done


    echo


    # ------------------------------------------------
    # acme.sh
    # ------------------------------------------------

    /root/.acme.sh/acme.sh \
        --issue \
        --dns dns_cf \
        "${DOMAIN_ARGS[@]}" \
        --keylength "$KEYLEN" \
        --server letsencrypt \
        --dnssleep 60 \
        >> "$LOG_FILE" 2>&1

}


# ==================================================
# ECC → RSA
# ==================================================

if issue ec-256; then

    CERT_SUFFIX="_ecc"

    echo
    echo "[INFO] ECC-256 证书申请成功"

else

    echo
    echo "[WARN] ECC-256 申请失败"
    echo "[WARN] 自动切换 RSA-4096"

    if issue 4096; then

        CERT_SUFFIX=""

        echo
        echo "[INFO] RSA-4096 证书申请成功"

    else

        echo
        echo "[ERROR] ECC-256 和 RSA-4096 均申请失败"
        echo "[ERROR] 请查看日志：$LOG_FILE"

        exit 1

    fi

fi


# ==================================================
# 安装证书
#
# 这里非常重要：
# --install-cert 会建立 acme.sh 的证书安装配置。
#
# 以后 acme.sh 自动续期成功后，
# 会继续更新：
#
# /root/cert/private.key
# /root/cert/public.crt
#
# ==================================================

echo
echo "===================================="
echo " 安装证书"
echo "===================================="
echo


if [ "$CERT_SUFFIX" = "_ecc" ]; then

    /root/.acme.sh/acme.sh \
        --install-cert \
        -d "$DOMAIN" \
        --ecc \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/public.crt" \
        >> "$LOG_FILE" 2>&1

else

    /root/.acme.sh/acme.sh \
        --install-cert \
        -d "$DOMAIN" \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/public.crt" \
        >> "$LOG_FILE" 2>&1

fi


# ==================================================
# 设置权限
# ==================================================

chmod 600 "$CERT_DIR/private.key"
chmod 644 "$CERT_DIR/public.crt"


# ==================================================
# 安装自动续期 Cron
# ==================================================

echo "[INFO] 安装 acme.sh 自动续期任务..."

if /root/.acme.sh/acme.sh --install-cronjob >> "$LOG_FILE" 2>&1; then

    echo "[INFO] 自动续期任务安装成功"

else

    echo "[WARN] 自动续期任务安装失败"
    echo "[WARN] 请检查：$LOG_FILE"

fi


# ==================================================
# 显示续期信息
# ==================================================

echo
echo "===================================="
echo " 自动续期配置"
echo "===================================="
echo

echo "acme.sh："
echo "  /root/.acme.sh/acme.sh"

echo
echo "证书安装目录："
echo "  $CERT_DIR"

echo
echo "证书文件："
echo "  $CERT_DIR/private.key"
echo "  $CERT_DIR/public.crt"

echo
echo "日志："
echo "  $LOG_FILE"

echo
echo "===================================="
echo "       ✅ 证书签发成功"
echo "===================================="
echo


# ==================================================
# 显示最终域名
# ==================================================

echo "证书包含以下域名："

for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
    echo "  $CERT_DOMAIN"
done

echo


# ==================================================
# 显示 acme.sh 证书列表
# ==================================================

echo "当前 acme.sh 证书："
echo

/root/.acme.sh/acme.sh --list 2>/dev/null || true

echo
echo "===================================="
