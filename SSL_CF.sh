```bash
#!/bin/bash

# ==================================================
# Cloudflare DNS + acme.sh
#
# 证书申请模式：
#
# 1. 主域名 + 通配符
#    例如：
#      example.com
#      *.example.com
#
# 2. 多个指定域名
#    例如：
#      node.example.com
#      api.example.com
#      www.example.net
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
# - 申请过程实时显示
#
# ==================================================

set -o pipefail

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

    # 普通域名
    if [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
        return 0
    fi

    return 1
}


# ==================================================
# 自动生成随机邮箱
#
# 仅用于 Let's Encrypt ACME 注册。
# 不再要求用户手动输入。
# ==================================================

generate_random_email() {

    local RANDOM_ID

    RANDOM_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"

    echo "acme-${RANDOM_ID}@example.com"
}


# ==================================================
# 新建配置
# ==================================================

configure_new() {

    echo
    echo "=============================================="
    echo "        Cloudflare SSL 证书配置"
    echo "=============================================="
    echo

    echo "请输入 Cloudflare API Token。"
    echo "Token 需要具有对应 Cloudflare Zone 的 DNS 编辑权限。"
    echo

    read -r -p "Cloudflare API Token: " CF_Token

    if [ -z "$CF_Token" ]; then
        echo
        echo "[ERROR] Cloudflare API Token 不能为空"
        exit 1
    fi


    echo
    echo "=============================================="
    echo "请选择证书申请模式"
    echo "=============================================="
    echo
    echo "  1. 主域名 + 通配符"
    echo "     说明："
    echo "     输入一个主域名后，自动申请两项："
    echo "       example.com"
    echo "       *.example.com"
    echo
    echo "     适合：需要整个主域名及其所有子域名"
    echo
    echo "  2. 多个指定域名"
    echo "     说明："
    echo "     只申请你明确输入的域名，不自动添加通配符。"
    echo "     可以填写多个域名，也可以来自不同主域名。"
    echo "     例如："
    echo "       node.example.com"
    echo "       api.example.com"
    echo "       www.example.net"
    echo
    echo "     上述域名会签发到同一张 SAN 证书中。"
    echo
    echo "=============================================="
    echo

    while true; do

        read -r -p "请选择 [1/2]: " CERT_MODE

        case "$CERT_MODE" in

            # ==================================================
            # 模式 1
            # 主域名 + 通配符
            # ==================================================

            1)

                echo
                echo "----------------------------------------------"
                echo "模式 1：主域名 + 通配符"
                echo "----------------------------------------------"
                echo
                echo "例如输入："
                echo "  example.com"
                echo
                echo "将自动申请："
                echo "  example.com"
                echo "  *.example.com"
                echo

                read -r -p "请输入主域名: " DOMAIN

                if ! validate_domain "$DOMAIN"; then
                    echo
                    echo "[ERROR] 域名格式不正确：$DOMAIN"
                    echo
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
                echo "----------------------------------------------"
                echo "模式 2：多个指定域名"
                echo "----------------------------------------------"
                echo
                echo "只申请你输入的域名。"
                echo "不会自动添加 *.域名。"
                echo
                echo "每行输入一个域名。"
                echo "输入空行结束。"
                echo
                echo "例如："
                echo "  node.example.com"
                echo "  api.example.com"
                echo "  www.example.net"
                echo
                echo "最终将生成一张包含上述域名的 SAN 证书。"
                echo

                DOMAIN_LIST=()

                while true; do

                    read -r -p "域名: " INPUT_DOMAIN

                    # 空行结束
                    if [ -z "$INPUT_DOMAIN" ]; then
                        break
                    fi


                    # 域名检查
                    if ! validate_domain "$INPUT_DOMAIN"; then
                        echo
                        echo "[WARN] 域名格式不正确，跳过：$INPUT_DOMAIN"
                        echo
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
                        echo
                        echo "[WARN] 域名已经存在，跳过：$INPUT_DOMAIN"
                        echo
                        continue
                    fi


                    DOMAIN_LIST+=("$INPUT_DOMAIN")

                    echo "[OK] 已添加：$INPUT_DOMAIN"

                done


                if [ "${#DOMAIN_LIST[@]}" -eq 0 ]; then
                    echo
                    echo "[ERROR] 至少需要输入一个域名"
                    echo
                    continue
                fi


                # 第一个域名作为 acme.sh 证书主标识
                DOMAIN="${DOMAIN_LIST[0]}"

                # 保存为空格分隔
                DOMAINS="${DOMAIN_LIST[*]}"

                break
                ;;


            *)
                echo
                echo "[ERROR] 请输入 1 或 2"
                echo
                ;;

        esac

    done


    # ==================================================
    # 自动生成邮箱
    # ==================================================

    ACME_EMAIL="$(generate_random_email)"


    echo
    echo "=============================================="
    echo "配置完成"
    echo "=============================================="
    echo
    echo "申请模式："

    if [ "$CERT_MODE" = "1" ]; then
        echo "  主域名 + 通配符"
    else
        echo "  多个指定域名"
    fi

    echo
    echo "ACME 注册邮箱："
    echo "  $ACME_EMAIL"
    echo
    echo "该邮箱由脚本自动生成，无需人工输入。"
    echo


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

    echo "[INFO] 配置已保存：$CONF_FILE"
}


# ==================================================
# 读取配置
# ==================================================

if [ -f "$CONF_FILE" ]; then

    source "$CONF_FILE"

    echo
    echo "=============================================="
    echo "检测到已有配置"
    echo "=============================================="
    echo
    echo "[INFO] 配置文件：$CONF_FILE"
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
    # 自动恢复为原模式：
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
        echo
        echo "旧配置将继续使用原有证书模式："
        echo
        echo "  $DOMAIN"
        echo "  *.$DOMAIN"
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
# 显示本次证书申请域名
# ==================================================

echo
echo "=============================================="
echo "        本次证书申请信息"
echo "=============================================="
echo

if [ "$CERT_MODE" = "1" ]; then
    echo "申请模式：主域名 + 通配符"
else
    echo "申请模式：多个指定域名"
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
echo "=============================================="
echo


# ==================================================
# 检查 curl
# ==================================================

if ! command -v curl >/dev/null 2>&1; then

    echo "[INFO] 未检测到 curl"
    echo "[INFO] 正在安装 curl..."

    if command -v apt-get >/dev/null 2>&1; then

        apt-get update
        apt-get install -y curl

    else

        echo "[ERROR] 系统没有 apt-get，请手动安装 curl"
        exit 1

    fi

fi


# ==================================================
# 安装 acme.sh
# ==================================================

if [ ! -f /root/.acme.sh/acme.sh ]; then

    echo
    echo "=============================================="
    echo "        安装 acme.sh"
    echo "=============================================="
    echo

    echo "[INFO] 未检测到 acme.sh"
    echo "[INFO] 开始安装..."
    echo

    if curl https://get.acme.sh | sh; then

        echo
        echo "[OK] acme.sh 安装完成"

    else

        echo
        echo "[ERROR] acme.sh 安装失败"
        exit 1

    fi

fi


export PATH="$PATH:/root/.acme.sh"


# ==================================================
# 检查 acme.sh
# ==================================================

if [ ! -f /root/.acme.sh/acme.sh ]; then

    echo
    echo "[ERROR] 找不到：/root/.acme.sh/acme.sh"
    exit 1

fi


echo
echo "[INFO] acme.sh 版本："
/root/.acme.sh/acme.sh --version || true
echo


# ==================================================
# Let's Encrypt 注册
#
# 注意：
# 邮箱已经自动生成，不再人工输入。
# ==================================================

echo
echo "=============================================="
echo "        Let's Encrypt ACME 账户"
echo "=============================================="
echo

echo "[INFO] 注册/检查 ACME 账户"
echo "[INFO] 邮箱：$ACME_EMAIL"
echo

/root/.acme.sh/acme.sh \
    --register-account \
    -m "$ACME_EMAIL" \
    --server letsencrypt \
    2>&1 | tee -a "$LOG_FILE"

REGISTER_RESULT=${PIPESTATUS[0]}

if [ "$REGISTER_RESULT" -eq 0 ]; then

    echo
    echo "[OK] Let's Encrypt ACME 账户准备完成"

else

    echo
    echo "[WARN] ACME 账户注册命令返回：$REGISTER_RESULT"
    echo "[WARN] 如果账户已经存在，可以继续尝试申请证书"

fi


# ==================================================
# 签发证书
# ==================================================

issue() {

    local KEYLEN="$1"

    echo
    echo "================================================"
    echo "        开始申请证书"
    echo "================================================"
    echo
    echo "[INFO] 密钥类型：$KEYLEN"
    echo "[INFO] DNS 验证方式：Cloudflare DNS-01"
    echo "[INFO] CA：Let's Encrypt"
    echo "[INFO] DNS 等待时间：60 秒"
    echo
    echo "本次申请域名："
    echo

    local DOMAIN_ARGS=()

    for CERT_DOMAIN in "${DOMAIN_LIST[@]}"; do

        echo "  - $CERT_DOMAIN"

        DOMAIN_ARGS+=(
            -d "$CERT_DOMAIN"
        )

    done

    echo
    echo "------------------------------------------------"
    echo "        acme.sh 开始执行"
    echo "------------------------------------------------"
    echo

    # ==================================================
    # 重点：
    #
    # 不再把申请过程完全重定向到日志。
    #
    # 现在：
    # 终端实时显示
    # +
    # 同时写入 acme.log
    #
    # PIPESTATUS 用于取得 acme.sh 的真实退出码。
    # ==================================================

    /root/.acme.sh/acme.sh \
        --issue \
        --dns dns_cf \
        "${DOMAIN_ARGS[@]}" \
        --keylength "$KEYLEN" \
        --server letsencrypt \
        --dnssleep 60 \
        2>&1 | tee -a "$LOG_FILE"

    local RESULT=${PIPESTATUS[0]}

    echo
    echo "------------------------------------------------"

    if [ "$RESULT" -eq 0 ]; then

        echo "[OK] acme.sh 证书申请成功"

    else

        echo "[ERROR] acme.sh 证书申请失败"
        echo "[ERROR] 返回代码：$RESULT"
        echo "[ERROR] 详细日志：$LOG_FILE"

    fi

    echo "------------------------------------------------"
    echo

    return "$RESULT"
}


# ==================================================
# ECC → RSA
# ==================================================

echo
echo "================================================"
echo "        开始证书签发"
echo "================================================"
echo


echo "[STEP 1/2] 优先申请 ECC-256 证书"
echo


if issue ec-256; then

    CERT_SUFFIX="_ecc"

    echo
    echo "================================================"
    echo "        ECC-256 证书申请成功"
    echo "================================================"
    echo

else

    echo
    echo "================================================"
    echo "        ECC-256 申请失败"
    echo "================================================"
    echo
    echo "[WARN] ECC-256 证书申请失败。"
    echo "[WARN] 将继续尝试 RSA-4096。"
    echo
    echo "[STEP 2/2] 开始申请 RSA-4096 证书"
    echo


    if issue 4096; then

        CERT_SUFFIX=""

        echo
        echo "================================================"
        echo "        RSA-4096 证书申请成功"
        echo "================================================"
        echo

    else

        echo
        echo "================================================"
        echo "        ❌ 证书申请失败"
        echo "================================================"
        echo
        echo "ECC-256 和 RSA-4096 均申请失败。"
        echo
        echo "请查看完整日志："
        echo "  $LOG_FILE"
        echo

        exit 1

    fi

fi


# ==================================================
# 安装证书
# ==================================================

echo
echo "================================================"
echo "        安装证书"
echo "================================================"
echo

echo "[INFO] 目标目录：$CERT_DIR"
echo
echo "[INFO] 私钥："
echo "  $CERT_DIR/private.key"
echo
echo "[INFO] 完整证书链："
echo "  $CERT_DIR/public.crt"
echo


if [ "$CERT_SUFFIX" = "_ecc" ]; then

    echo "[INFO] 正在安装 ECC 证书..."
    echo

    /root/.acme.sh/acme.sh \
        --install-cert \
        -d "$DOMAIN" \
        --ecc \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/public.crt" \
        2>&1 | tee -a "$LOG_FILE"

    INSTALL_RESULT=${PIPESTATUS[0]}

else

    echo "[INFO] 正在安装 RSA 证书..."
    echo

    /root/.acme.sh/acme.sh \
        --install-cert \
        -d "$DOMAIN" \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/public.crt" \
        2>&1 | tee -a "$LOG_FILE"

    INSTALL_RESULT=${PIPESTATUS[0]}

fi


if [ "$INSTALL_RESULT" -ne 0 ]; then

    echo
    echo "[ERROR] 证书安装失败"
    echo "[ERROR] 返回代码：$INSTALL_RESULT"
    echo "[ERROR] 请查看：$LOG_FILE"
    exit 1

fi


echo
echo "[OK] 证书安装成功"


# ==================================================
# 设置证书权限
# ==================================================

echo
echo "[INFO] 设置证书文件权限..."

chmod 600 "$CERT_DIR/private.key"
chmod 644 "$CERT_DIR/public.crt"

echo "[OK] 权限设置完成"


# ==================================================
# 安装自动续期 Cron
# ==================================================

echo
echo "================================================"
echo "        配置自动续期"
echo "================================================"
echo

echo "[INFO] 安装 acme.sh 自动续期任务..."
echo


/root/.acme.sh/acme.sh \
    --install-cronjob \
    2>&1 | tee -a "$LOG_FILE"

CRON_RESULT=${PIPESTATUS[0]}


if [ "$CRON_RESULT" -eq 0 ]; then

    echo
    echo "[OK] 自动续期任务安装成功"

else

    echo
    echo "[WARN] 自动续期任务安装命令返回：$CRON_RESULT"
    echo "[WARN] 请检查：$LOG_FILE"

fi


# ==================================================
# 显示当前证书信息
# ==================================================

echo
echo "================================================"
echo "        当前 acme.sh 证书"
echo "================================================"
echo

/root/.acme.sh/acme.sh --list 2>&1 | tee -a "$LOG_FILE" || true


# ==================================================
# 验证证书文件
# ==================================================

echo
echo "================================================"
echo "        验证证书文件"
echo "================================================"
echo


if [ -f "$CERT_DIR/private.key" ]; then
    echo "[OK] 私钥存在：$CERT_DIR/private.key"
else
    echo "[ERROR] 私钥不存在：$CERT_DIR/private.key"
fi


if [ -f "$CERT_DIR/public.crt" ]; then
    echo "[OK] 证书存在：$CERT_DIR/public.crt"
else
    echo "[ERROR] 证书不存在：$CERT_DIR/public.crt"
fi


# ==================================================
# 显示证书详细信息
# ==================================================

if command -v openssl >/dev/null 2>&1 && [ -f "$CERT_DIR/public.crt" ]; then

    echo
    echo "================================================"
    echo "        证书详细信息"
    echo "================================================"
    echo

    openssl x509 \
        -in "$CERT_DIR/public.crt" \
        -noout \
        -subject \
        -issuer \
        -serial \
        -dates \
        -ext subjectAltName \
        2>&1 | tee -a "$LOG_FILE" || true

fi


# ==================================================
# 最终结果
# ==================================================

echo
echo
echo "================================================"
echo "          ✅ SSL 证书配置完成"
echo "================================================"
echo

echo "申请模式："

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
echo "证书文件："
echo "  $CERT_DIR/public.crt"

echo
echo "私钥文件："
echo "  $CERT_DIR/private.key"

echo
echo "日志文件："
echo "  $LOG_FILE"

echo
echo "配置文件："
echo "  $CONF_FILE"

echo
echo "ACME 邮箱："
echo "  $ACME_EMAIL"

echo
echo "自动续期："
echo "  已配置 acme.sh Cron"

echo
echo "================================================"
echo "        后续 acme.sh 将自动检查并续签"
echo "================================================"
echo
```
