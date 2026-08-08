```bash
#!/bin/bash

# ==================================================
# Cloudflare DNS + acme.sh
#
# 支持两种证书申请模式：
#
# 1. 主域名 + *.通配符（原有模式）
# 2. 指定多个域名（新增模式）
#
# 原有功能全部保留：
# - Cloudflare DNS-01
# - Let's Encrypt
# - 自动缓存参数
# - ECC P-256 优先
# - ECC 失败自动切换 RSA 4096
# - 证书安装到 /root/cert/
# - 自动安装 acme.sh 定时任务
# - 原有配置文件兼容
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
# 域名验证
# ==================================================

validate_domain() {

    local domain="$1"

    # 基本域名格式检查
    if [[ ! "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
        return 1
    fi

    return 0
}


# ==================================================
# 新配置
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

            1)
                echo
                read -p "请输入主域名 (如 example.com): " DOMAIN

                if ! validate_domain "$DOMAIN"; then
                    echo "[ERROR] 域名格式不正确：$DOMAIN"
                    continue
                fi

                # 原有模式
                # 自动申请：
                # example.com
                # *.example.com

                DOMAINS="$DOMAIN *.$DOMAIN"

                break
                ;;

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
                        echo "[WARN] 域名格式不正确，已跳过：$INPUT_DOMAIN"
                        continue
                    fi

                    # 防止重复
                    DUPLICATE=0

                    for EXISTING_DOMAIN in "${DOMAIN_LIST[@]}"; do
                        if [ "$EXISTING_DOMAIN" = "$INPUT_DOMAIN" ]; then
                            DUPLICATE=1
                            break
                        fi
                    done

                    if [ "$DUPLICATE" -eq 1 ]; then
                        echo "[WARN] 域名已存在，跳过：$INPUT_DOMAIN"
                        continue
                    fi

                    DOMAIN_LIST+=("$INPUT_DOMAIN")

                    echo "[OK] 已添加：$INPUT_DOMAIN"

                done

                if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then
                    echo "[ERROR] 至少需要输入一个域名"
                    continue
                fi

                # 第一个域名作为 acme.sh 证书标识
                DOMAIN="${DOMAIN_LIST[0]}"

                # 转换成空格分隔保存
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


    # ---------- 保存配置 ----------

    cat >"$CONF_FILE" <<EOF
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
    echo "===================================="
    echo " 已发现缓存配置"
    echo "===================================="
    echo
    echo "配置文件：$CONF_FILE"
    echo

    # ------------------------------------------------
    # 兼容旧版本配置
    #
    # 旧版本只有：
    # CF_Token
    # DOMAIN
    # ACME_EMAIL
    #
    # 没有 CERT_MODE / DOMAINS
    #
    # 默认继续使用原来的：
    # DOMAIN
    # *.DOMAIN
    # ------------------------------------------------

    if [ -z "${CERT_MODE:-}" ]; then

        CERT_MODE="1"

        if [ -n "${DOMAIN:-}" ]; then
            DOMAINS="$DOMAIN *.$DOMAIN"
        fi

        echo "[INFO] 检测到旧版配置"
        echo "[INFO] 将继续使用原有模式："
        echo "       $DOMAIN"
        echo "       *.$DOMAIN"
        echo

    fi


    # ------------------------------------------------
    # 让用户选择是否使用缓存
    #
    # 默认 Enter = 使用缓存
    # 因此原来的重复运行行为仍然保持。
    # ------------------------------------------------

    read -p "是否使用以上缓存配置？[Y/n]: " USE_CACHE

    if [[ "$USE_CACHE" =~ ^[Nn]$ ]]; then

        configure_new

        # 重新读取配置
        source "$CONF_FILE"

    else

        echo
        echo "[INFO] 使用缓存配置"

    fi

else

    configure_new

fi


# ==================================================
# 再次读取配置
# ==================================================

source "$CONF_FILE"


# ==================================================
# 构建域名数组
# ==================================================

DOMAIN_LIST=()

if [ "$CERT_MODE" = "1" ]; then

    # ------------------------------------------------
    # 原有模式
    #
    # example.com
    # *.example.com
    # ------------------------------------------------

    if [ -z "${DOMAIN:-}" ]; then
        echo "[ERROR] DOMAIN 未配置"
        exit 1
    fi

    DOMAIN_LIST=(
        "$DOMAIN"
        "*.$DOMAIN"
    )

else

    # ------------------------------------------------
    # 新模式
    #
    # 使用指定域名
    # ------------------------------------------------

    if [ -z "${DOMAINS:-}" ]; then
        echo "[ERROR] DOMAINS 未配置"
        exit 1
    fi

    read -r -a DOMAIN_LIST <<< "$DOMAINS"

    if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then
        echo "[ERROR] 没有可用的域名"
        exit 1
    fi

fi


# ==================================================
# 显示最终申请域名
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

    echo "[INFO] 未检测到 acme.sh，开始安装..."

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
# 注册 Let's Encrypt 账号
# ==================================================

echo "[INFO] 注册 / 检查 Let's Encrypt 账号..."

/root/.acme.sh/acme.sh \
    --register-account \
    -m "$ACME_EMAIL" \
    --server letsencrypt \
    >>"$LOG_FILE" 2>&1 || true


# ==================================================
# 签发函数
# ==================================================

issue() {

    local KEYLEN="$1"

    echo
    echo "===================================="
    echo " 开始申请证书"
    echo "===================================="

    echo "[INFO] Key 类型：$KEYLEN"
    echo

    echo "[INFO] 申请域名："

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
        echo "       $CERT_DOMAIN"
    done

    echo


    # ------------------------------------------------
    # 构造 acme.sh 参数
    # ------------------------------------------------

    local DOMAIN_ARGS=()

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do

        DOMAIN_ARGS+=(
            -d "$CERT_DOMAIN"
        )

    done


    # ------------------------------------------------
    # 调用 acme.sh
    # ------------------------------------------------

    /root/.acme.sh/acme.sh \
        --issue \
        --dns dns_cf \
        "${DOMAIN_ARGS[@]}" \
        --keylength "$KEYLEN" \
        --server letsencrypt \
        --dnssleep 60 \
        >>"$LOG_FILE" 2>&1

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
    echo "[WARN] ECC 申请失败"
    echo "[WARN] 切换 RSA 4096"

    if issue 4096; then

        CERT_SUFFIX=""

        echo
        echo "[INFO] RSA-4096 证书申请成功"

    else

        echo
        echo "[ERROR] ECC 和 RSA 均申请失败"
        echo "[ERROR] 请查看：$LOG_FILE"

        exit 1

    fi

fi


# ==================================================
# 安装证书
# ==================================================

echo
echo "===================================="
echo " 安装证书"
echo "===================================="
echo


/root/.acme.sh/acme.sh \
    --install-cert \
    -d "$DOMAIN" \
    --key-file "$CERT_DIR/private.key" \
    --fullchain-file "$CERT_DIR/public.crt" \
    ${CERT_SUFFIX:+--ecc} \
    >>"$LOG_FILE" 2>&1


# ==================================================
# 设置权限
# ==================================================

chmod 600 "$CERT_DIR/private.key"
chmod 644 "$CERT_DIR/public.crt"


# ==================================================
# 自动续期
# ==================================================

echo "[INFO] 安装 acme.sh 自动续期任务..."

/root/.acme.sh/acme.sh \
    --install-cronjob \
    >>"$LOG_FILE" 2>&1


# ==================================================
# 完成
# ==================================================

echo
echo "===================================="
echo "      ✅ 证书签发成功"
echo "===================================="
echo

echo "申请模式："

if [ "$CERT_MODE" = "1" ]; then

    echo "  主域名 + 通配符"

else

    echo "  指定域名"

fi

echo
echo "证书域名："

for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do
    echo "  $CERT_DOMAIN"
done

echo
echo "私钥: $CERT_DIR/private.key"
echo "证书: $CERT_DIR/public.crt"
echo "日志: $LOG_FILE"
echo "配置: $CONF_FILE"

echo
echo "===================================="
echo
```
