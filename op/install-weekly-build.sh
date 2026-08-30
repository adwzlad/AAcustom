#!/bin/bash

set -euo pipefail

# ============================================================
# ImmortalWrt 每周自动编译环境一键部署
#
# GitHub:
#   https://github.com/adwzlad/AAcustom/tree/main/op
#
# 本脚本必须由 root 执行
#
# 功能：
#
#   1. 检查 op 用户，不存在则创建普通用户 op
#   2. 检查 /home/op/immortalwrt
#      不存在则由 op 用户自动 clone
#   3. 安装 ImmortalWrt 编译依赖
#   4. 安装 tmux / cron
#   5. 检查所有需要的程序
#   6. 从 GitHub 下载三个编译脚本
#   7. 设置脚本权限和所有者
#   8. 配置 op 用户每周一次的 cron
#   9. 最终检查
#
# 注意：
#
#   root 只负责部署。
#
#   ImmortalWrt 编译始终由普通用户 op 执行。
#
#   不生成编译日志文件。
#
#   不检查硬盘空间。
#   因为已有正常的 ImmortalWrt 源码时，
#   不应该因为剩余空间低于官方建议值而阻止部署。
# ============================================================


# ============================================================
# 配置
# ============================================================

OP_USER="op"
OP_HOME="/home/op"

IMMORTALWRT_DIR="$OP_HOME/immortalwrt"

IMMORTALWRT_REPO="https://github.com/immortalwrt/immortalwrt"

GITHUB_RAW_BASE="https://raw.githubusercontent.com/adwzlad/AAcustom/main/op"

BUILD_SCRIPT="$OP_HOME/weekly-build.sh"
RUN_SCRIPT="$OP_HOME/weekly-build-run.sh"
LAUNCHER_SCRIPT="$OP_HOME/weekly-build-launcher.sh"

RUNNING_FILE="$OP_HOME/.weekly-build.running"

# ============================================================
# 每周执行时间
#
# 这里是：
#   每周日 03:00
#
# 如果以后需要修改，只改这里即可。
# ============================================================

CRON_SCHEDULE="0 3 * * 0"

CRON_MARK="# ImmortalWrt weekly build - AAcustom"


# ============================================================
# 输出函数
# ============================================================

info() {
    echo
    echo "[INFO] $*"
}

ok() {
    echo "[ OK ] $*"
}

warn() {
    echo "[WARN] $*"
}

error() {
    echo "[ERROR] $*" >&2
}


# ============================================================
# 必须 root
# ============================================================

if [ "$(id -u)" -ne 0 ]; then

    error "此部署脚本必须由 root 执行。"

    echo
    echo "请使用："
    echo
    echo "  sudo bash $0"
    echo

    exit 1

fi

ok "当前用户：root"


# ============================================================
# 设置 PATH
#
# cron 环境 PATH 比较简单。
# 这里部署脚本本身使用完整系统 PATH。
# ============================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


# ============================================================
# 检查操作系统
# ============================================================

if [ ! -f /etc/os-release ]; then

    error "无法检测操作系统。"

    exit 1

fi

. /etc/os-release


case "${ID:-}" in

    debian)

        ok "操作系统：${PRETTY_NAME:-Debian}"

        ;;

    ubuntu)

        ok "操作系统：${PRETTY_NAME:-Ubuntu}"

        ;;

    *)

        error "本脚本只支持 Debian / Ubuntu。"

        error "当前系统：${PRETTY_NAME:-unknown}"

        exit 1

        ;;

esac


# ============================================================
# 检查 /home
# ============================================================

if [ ! -d /home ]; then

    error "/home 目录不存在。"

    exit 1

fi


# ============================================================
# 检查 op 用户
#
# 不存在：
#   创建普通用户
#
# 已存在：
#   不修改
#
# 不加入 sudo / wheel。
# ============================================================

info "检查用户 $OP_USER ..."


if id "$OP_USER" >/dev/null 2>&1; then

    ok "用户 $OP_USER 已存在"

else

    info "用户 $OP_USER 不存在，正在创建普通用户..."

    useradd \
        --create-home \
        --home-dir "$OP_HOME" \
        --shell /bin/bash \
        "$OP_USER"

    ok "普通用户 $OP_USER 创建完成"

fi


# ============================================================
# 检查 op HOME
# ============================================================

REAL_HOME=$(getent passwd "$OP_USER" | cut -d: -f6)


if [ "$REAL_HOME" != "$OP_HOME" ]; then

    error "$OP_USER 的 HOME 目录不是 $OP_HOME"

    error "当前 HOME：$REAL_HOME"

    error "为了避免 cron / tmux / 编译目录错误，停止部署。"

    exit 1

fi


ok "$OP_USER HOME：$OP_HOME"


# ============================================================
# 确认 op 不是 root
# ============================================================

OP_UID=$(id -u "$OP_USER")


if [ "$OP_UID" -eq 0 ]; then

    error "$OP_USER 的 UID 为 0。"

    error "$OP_USER 不能是 root 用户。"

    exit 1

fi


ok "$OP_USER UID：$OP_UID（普通用户）"


# ============================================================
# 检查管理员组
#
# 如果现有 op 已经属于 sudo / wheel，
# 不自动删除已有权限，只进行警告。
#
# 新创建的 op 不会主动加入这些组。
# ============================================================

OP_GROUPS=$(id -nG "$OP_USER" 2>/dev/null || true)


if echo "$OP_GROUPS" | grep -Eq '(^| )(sudo|wheel)( |$)'; then

    warn "$OP_USER 当前属于 sudo/wheel 管理员组。"

    warn "本脚本不会自动删除现有管理员权限。"

else

    ok "$OP_USER 没有加入 sudo/wheel"

fi


# ============================================================
# 确保 HOME 本身属于 op
#
# 注意：
#   不递归修改 /home/op。
#
#   特别是不修改已有 immortalwrt 的所有权。
# ============================================================

chown "$OP_USER:$OP_USER" "$OP_HOME"

ok "$OP_HOME 所有权检查完成"


# ============================================================
# 更新 APT
# ============================================================

export DEBIAN_FRONTEND=noninteractive


info "更新 APT 软件包索引..."


apt-get update


ok "APT 软件包索引更新完成"


# ============================================================
# ImmortalWrt 编译依赖
#
# 按 ImmortalWrt 官方 Debian / Ubuntu 编译环境准备。
# ============================================================

IMMORTALWRT_PACKAGES="
ack
antlr3
asciidoc
autoconf
automake
autopoint
binutils
bison
build-essential
bzip2
ccache
clang
cmake
cpio
curl
device-tree-compiler
ecj
fastjar
flex
gawk
gettext
git
gperf
haveged
help2man
intltool
libelf-dev
libglib2.0-dev
libgmp3-dev
libltdl-dev
libmpc-dev
libmpfr-dev
libncurses-dev
libpython3-dev
libreadline-dev
libssl-dev
libtool
libyaml-dev
libz-dev
lld
llvm
lrzsz
mkisofs
msmtp
nano
ninja-build
p7zip
p7zip-full
patch
pkgconf
python3
python3-pip
python3-ply
python3-docutils
python3-pyelftools
qemu-utils
re2c
rsync
scons
squashfs-tools
subversion
swig
texinfo
uglifyjs
upx-ucl
unzip
vim
wget
xmlto
xxd
zlib1g-dev
zstd
"


# ============================================================
# amd64 专用依赖
#
# 只有 amd64 安装 multilib。
#
# ARM64 等架构不安装这些。
# ============================================================

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)


if [ "$ARCH" = "amd64" ]; then

    IMMORTALWRT_PACKAGES="$IMMORTALWRT_PACKAGES
gcc-multilib
g++-multilib
gnutls-dev
lib32gcc-s1
libc6-dev-i386
"

fi


# ============================================================
# 自动编译额外依赖
#
# tmux：
#   编译过程专用 session
#
# cron：
#   每周自动启动
#
# util-linux：
#   提供 flock
# ============================================================

AUTOMATION_PACKAGES="
cron
tmux
util-linux
"


# ============================================================
# 安装软件包
# ============================================================

info "安装 ImmortalWrt 编译依赖和自动任务依赖..."


apt-get install -y \
    $IMMORTALWRT_PACKAGES \
    $AUTOMATION_PACKAGES


ok "软件包安装完成"


# ============================================================
# 检查 cron 服务
# ============================================================

info "检查 cron 服务..."


if command -v systemctl >/dev/null 2>&1; then

    systemctl enable cron >/dev/null 2>&1 || true

    systemctl restart cron


    if systemctl is-active --quiet cron; then

        ok "cron 服务正在运行"

    else

        error "cron 服务没有正常运行"

        systemctl status cron --no-pager || true

        exit 1

    fi

else

    warn "系统没有 systemctl。"

    warn "无法自动确认 cron 服务状态。"

fi


# ============================================================
# 检查所有关键程序
# ============================================================

info "检查所有需要的程序..."


REQUIRED_COMMANDS="
bash
git
tmux
make
gcc
g++
clang
cmake
python3
curl
wget
rsync
bison
flex
gawk
gettext
patch
unzip
tar
gzip
xz
find
grep
sed
awk
cat
date
kill
rm
flock
crontab
nproc
"


MISSING_COMMANDS=""


for CMD in $REQUIRED_COMMANDS; do

    if command -v "$CMD" >/dev/null 2>&1; then

        case "$CMD" in

            git)

                VERSION=$(git --version 2>/dev/null || true)

                ;;

            tmux)

                VERSION=$(tmux -V 2>/dev/null || true)

                ;;

            make)

                VERSION=$(make --version 2>/dev/null | head -1 || true)

                ;;

            gcc)

                VERSION=$(gcc --version 2>/dev/null | head -1 || true)

                ;;

            g++)

                VERSION=$(g++ --version 2>/dev/null | head -1 || true)

                ;;

            clang)

                VERSION=$(clang --version 2>/dev/null | head -1 || true)

                ;;

            cmake)

                VERSION=$(cmake --version 2>/dev/null | head -1 || true)

                ;;

            python3)

                VERSION=$(python3 --version 2>/dev/null || true)

                ;;

            *)

                VERSION=$(command -v "$CMD")

                ;;

        esac


        printf '  [ OK ] %-15s %s\n' "$CMD" "$VERSION"


    else

        printf '  [FAIL] %-15s 未找到\n' "$CMD"

        MISSING_COMMANDS="$MISSING_COMMANDS $CMD"

    fi

done


if [ -n "$MISSING_COMMANDS" ]; then

    error "以下程序仍然缺失："

    error "$MISSING_COMMANDS"

    exit 1

fi


ok "所有关键程序检查通过"


# ============================================================
# 显示 CPU / 内存 / Swap
#
# 不作为部署失败条件。
#
# 特别适合：
#   1G RAM + 4G Swap
# ============================================================

info "检查系统资源..."


CPU_COUNT=$(nproc)


MEMORY_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)


MEMORY_GB=$(awk '
BEGIN {
    printf "%.1f", '"$MEMORY_KB"' / 1024 / 1024
}
')


SWAP_KB=$(awk '
/SwapTotal:/ {
    print $2
}
' /proc/meminfo)


SWAP_GB=$(awk '
BEGIN {
    printf "%.1f", '"$SWAP_KB"' / 1024 / 1024
}
')


echo
echo "CPU：${CPU_COUNT} 核"
echo "内存：${MEMORY_GB} GiB"
echo "Swap：${SWAP_GB} GiB"
echo "架构：${ARCH}"


if [ "$MEMORY_KB" -lt $((4 * 1024 * 1024)) ]; then

    warn "内存低于 ImmortalWrt 官方建议的 4 GiB。"

    warn "当前内存：${MEMORY_GB} GiB"

    warn "继续部署，不因为内存不足而退出。"

else

    ok "内存达到官方建议值"

fi


if [ "$SWAP_KB" -eq 0 ]; then

    warn "系统没有 Swap。"

else

    ok "Swap：${SWAP_GB} GiB"

fi


# ============================================================
# 注意：
#
# 这里故意不检查磁盘空间。
#
# 不执行：
#   df
#
# 不判断：
#   25 GiB
#
# 原因：
#
#   用户已经存在一个可以正常编译的
#   /home/op/immortalwrt。
#
#   当前剩余空间不足 25 GiB 不应该阻止
#   自动部署。
# ============================================================

ok "跳过磁盘空间检查"


# ============================================================
# 检查 PATH
#
# ImmortalWrt 编译路径不建议包含空格或非 ASCII。
# ============================================================

case ":$PATH:" in

    *" "*)

        error "PATH 中存在空格。"

        error "请先修正 PATH。"

        exit 1

        ;;

esac


if printf '%s' "$PATH" | LC_ALL=C grep -q '[^ -~]'; then

    error "PATH 中存在非 ASCII 字符。"

    error "请先修正 PATH。"

    exit 1

fi


ok "PATH 检查通过"


# ============================================================
# 检查 ImmortalWrt 源码
#
# 情况 1：
#
#   /home/op/immortalwrt 不存在
#
#   → 由 op 用户 clone
#
#
# 情况 2：
#
#   目录存在，但是不是 Git 仓库
#
#   → 停止
#
#
# 情况 3：
#
#   已经是 Git 仓库
#
#   → 直接使用
#
# 不会覆盖已有源码。
# ============================================================

info "检查 ImmortalWrt 源码目录..."


if [ ! -e "$IMMORTALWRT_DIR" ]; then

    info "ImmortalWrt 源码不存在。"

    info "开始由普通用户 $OP_USER clone..."


    runuser -u "$OP_USER" -- \
        git clone \
        --single-branch \
        --filter=blob:none \
        "$IMMORTALWRT_REPO" \
        "$IMMORTALWRT_DIR"


    ok "ImmortalWrt 源码 clone 完成"


elif [ ! -d "$IMMORTALWRT_DIR" ]; then

    error "$IMMORTALWRT_DIR 已存在，但不是目录。"

    exit 1


elif [ ! -d "$IMMORTALWRT_DIR/.git" ]; then

    error "$IMMORTALWRT_DIR 已存在，但不是 Git 仓库。"

    error "为了避免覆盖已有数据，停止部署。"

    exit 1


else

    ok "ImmortalWrt Git 仓库已经存在"

fi


# ============================================================
# 检查 op 是否可以读写源码
# ============================================================

if ! runuser -u "$OP_USER" -- \
    test -r "$IMMORTALWRT_DIR"; then

    error "$OP_USER 无法读取：$IMMORTALWRT_DIR"

    exit 1

fi


if ! runuser -u "$OP_USER" -- \
    test -w "$IMMORTALWRT_DIR"; then

    error "$OP_USER 无法写入：$IMMORTALWRT_DIR"

    error "请检查现有 ImmortalWrt 源码目录权限。"

    exit 1

fi


ok "$OP_USER 可以读写 ImmortalWrt 源码"


# ============================================================
# 检查 Git
# ============================================================

info "检查 ImmortalWrt Git 状态..."


if ! runuser -u "$OP_USER" -- \
    git -C "$IMMORTALWRT_DIR" rev-parse --is-inside-work-tree \
    >/dev/null 2>&1; then

    error "ImmortalWrt Git 仓库检查失败。"

    exit 1

fi


CURRENT_BRANCH=$(
    runuser -u "$OP_USER" -- \
    git -C "$IMMORTALWRT_DIR" branch --show-current \
    2>/dev/null || true
)


CURRENT_COMMIT=$(
    runuser -u "$OP_USER" -- \
    git -C "$IMMORTALWRT_DIR" rev-parse --short HEAD \
    2>/dev/null || true
)


echo "当前分支：${CURRENT_BRANCH:-（detached HEAD）}"
echo "当前 Commit：${CURRENT_COMMIT:-unknown}"


ok "ImmortalWrt Git 仓库正常"


# ============================================================
# 检查 Git origin
# ============================================================

REMOTE_URL=$(
    runuser -u "$OP_USER" -- \
    git -C "$IMMORTALWRT_DIR" remote get-url origin \
    2>/dev/null || true
)


if [ -n "$REMOTE_URL" ]; then

    echo "origin：$REMOTE_URL"

    ok "Git origin 存在"

else

    warn "没有检测到 Git origin。"

    warn "现有源码仍然保留，但后续 weekly-build.sh 的 git fetch 可能失败。"

fi


# ============================================================
# 下载 GitHub 上的三个自动编译脚本
# ============================================================

info "从 GitHub 下载最新自动编译脚本..."


TMP_DIR=$(mktemp -d)


cleanup_tmp() {

    rm -rf "$TMP_DIR"

}


trap cleanup_tmp EXIT


curl -fsSL \
    "$GITHUB_RAW_BASE/weekly-build.sh" \
    -o "$TMP_DIR/weekly-build.sh"


curl -fsSL \
    "$GITHUB_RAW_BASE/weekly-build-run.sh" \
    -o "$TMP_DIR/weekly-build-run.sh"


curl -fsSL \
    "$GITHUB_RAW_BASE/weekly-build-launcher.sh" \
    -o "$TMP_DIR/weekly-build-launcher.sh"


ok "三个 GitHub 脚本下载成功"


# ============================================================
# Shell 语法检查
# ============================================================

info "检查三个 Shell 脚本语法..."


bash -n "$TMP_DIR/weekly-build.sh"

bash -n "$TMP_DIR/weekly-build-run.sh"

bash -n "$TMP_DIR/weekly-build-launcher.sh"


ok "三个脚本语法检查通过"


# ============================================================
# 安装三个脚本
#
# 已存在：
#   自动备份
#
# 新文件：
#   0755
#   op:op
# ============================================================

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')


for FILE in \
    weekly-build.sh \
    weekly-build-run.sh \
    weekly-build-launcher.sh
do

    SOURCE="$TMP_DIR/$FILE"

    TARGET="$OP_HOME/$FILE"


    if [ -f "$TARGET" ]; then

        BACKUP="$TARGET.backup-$TIMESTAMP"

        cp -a "$TARGET" "$BACKUP"

        chown "$OP_USER:$OP_USER" "$BACKUP"

        echo "旧文件备份：$BACKUP"

    fi


    install \
        -o "$OP_USER" \
        -g "$OP_USER" \
        -m 0755 \
        "$SOURCE" \
        "$TARGET"

done


ok "三个自动编译脚本安装完成"


# ============================================================
# 检查脚本
# ============================================================

for FILE in \
    "$BUILD_SCRIPT" \
    "$RUN_SCRIPT" \
    "$LAUNCHER_SCRIPT"
do

    if [ ! -f "$FILE" ]; then

        error "文件不存在：$FILE"

        exit 1

    fi


    if [ ! -x "$FILE" ]; then

        error "文件不可执行：$FILE"

        exit 1

    fi


    OWNER=$(stat -c '%U:%G' "$FILE")


    if [ "$OWNER" != "$OP_USER:$OP_USER" ]; then

        error "$FILE 所有者错误：$OWNER"

        exit 1

    fi

done


ok "三个脚本权限和所有者正常"


# ============================================================
# 配置 op 用户 crontab
#
# 只删除：
#
#   本脚本之前管理的任务
#
# 不影响：
#
#   op 用户自己的其他 cron。
# ============================================================

info "配置 $OP_USER 用户 crontab..."


CURRENT_CRONTAB=$(
    crontab -u "$OP_USER" -l 2>/dev/null || true
)


NEW_CRONTAB=$(
    printf '%s\n' "$CURRENT_CRONTAB" \
    | grep -vF "$CRON_MARK" \
    | grep -vF "$LAUNCHER_SCRIPT" \
    || true
)


# 删除空行
NEW_CRONTAB=$(
    printf '%s\n' "$NEW_CRONTAB" \
    | sed '/^[[:space:]]*$/d'
)


if [ -n "$NEW_CRONTAB" ]; then

    NEW_CRONTAB="${NEW_CRONTAB}"$'\n'

fi


NEW_CRONTAB="${NEW_CRONTAB}${CRON_MARK}"$'\n'

NEW_CRONTAB="${NEW_CRONTAB}${CRON_SCHEDULE} ${LAUNCHER_SCRIPT}"$'\n'


printf '%s' "$NEW_CRONTAB" \
    | crontab -u "$OP_USER" -


ok "$OP_USER crontab 配置完成"


# ============================================================
# 显示最终 crontab
# ============================================================

echo
echo "============================================================"
echo "$OP_USER 当前 crontab"
echo "============================================================"


crontab -u "$OP_USER" -l


# ============================================================
# 测试 op 用户运行 tmux
#
# 这里只测试 tmux 程序。
#
# 不创建正式的 tmux op 编译 session。
# 不启动编译。
# ============================================================

info "测试 op 用户 tmux..."


runuser -u "$OP_USER" -- \
    tmux -V


ok "op 用户可以使用 tmux"


# ============================================================
# 测试 op 用户 Shell 脚本
#
# 只进行 bash -n。
#
# 不启动实际编译。
# ============================================================

info "测试 op 用户自动编译脚本..."


runuser -u "$OP_USER" -- \
    bash -n "$BUILD_SCRIPT"


runuser -u "$OP_USER" -- \
    bash -n "$RUN_SCRIPT"


runuser -u "$OP_USER" -- \
    bash -n "$LAUNCHER_SCRIPT"


ok "op 用户脚本检查通过"


# ============================================================
# 检查 running 文件
#
# 如果旧的状态文件存在：
#
#   不删除
#
# 因为它可能代表当前正在运行的编译。
#
# 由 weekly-build-launcher.sh 自己判断 PID。
# ============================================================

if [ -f "$RUNNING_FILE" ]; then

    warn "发现已有运行状态文件：$RUNNING_FILE"

    warn "部署脚本不会删除它。"

else

    ok "没有发现旧的编译运行状态文件"

fi


# ============================================================
# 最终信息
# ============================================================

echo
echo
echo "============================================================"
echo "          ImmortalWrt 自动编译环境部署完成"
echo "============================================================"


echo
echo "运行用户："
echo "  $OP_USER"


echo
echo "源码目录："
echo "  $IMMORTALWRT_DIR"


echo
echo "编译脚本："
echo "  $BUILD_SCRIPT"


echo
echo "运行脚本："
echo "  $RUN_SCRIPT"


echo
echo "启动脚本："
echo "  $LAUNCHER_SCRIPT"


echo
echo "tmux 专用 Session："
echo "  op"


echo
echo "自动编译时间："
echo "  每周日 03:00"


echo
echo "Cron："
echo "  $CRON_SCHEDULE $LAUNCHER_SCRIPT"


echo
echo "============================================================"
echo "手动立即启动一次编译："
echo
echo "  sudo -u op $LAUNCHER_SCRIPT"
echo "============================================================"


echo
echo "查看编译过程："
echo
echo "  sudo -u op tmux attach-session -t op"
echo "============================================================"


echo
echo "如果已经切换到 op 用户："
echo
echo "  ~/weekly-build-launcher.sh"
echo
echo "  tmux attach-session -t op"
echo "============================================================"


echo
echo "部署脚本没有启动编译。"
echo "第一次编译可以手动启动，或者等待下一次 cron。"
echo


# ============================================================
# 完成
# ============================================================

exit 0
