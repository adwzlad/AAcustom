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
#      不存在则由 op 用户自动 clone ImmortalWrt
#   3. 安装 ImmortalWrt 官方编译依赖
#   4. 安装 tmux / cron
#   5. 检查所有需要的程序
#   6. 从 GitHub 下载三个编译脚本
#   7. 设置脚本权限和所有者
#   8. 配置 op 用户每周一次的 cron
#   9. 最终进行完整环境检查
#
# 注意：
#
#   root 只负责：
#     - 安装软件
#     - 创建用户
#     - 准备源码
#     - 部署脚本
#     - 配置 cron
#
#   ImmortalWrt 编译始终由普通用户 op 执行。
#
#   本脚本不会产生编译日志文件。
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

# 每周日 03:00
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
    echo "请执行："
    echo
    echo "  sudo bash $0"
    echo

    exit 1

fi

ok "当前用户：root"


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
# 检查 root 的 PATH
# ============================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


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
#   自动创建普通用户 op
#
# 已存在：
#   保留现有用户
#
# 不加入 sudo / wheel 等管理员组
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
# 确认 op HOME
# ============================================================

REAL_HOME=$(getent passwd "$OP_USER" | cut -d: -f6)

if [ "$REAL_HOME" != "$OP_HOME" ]; then

    error "$OP_USER 的 HOME 不是 $OP_HOME"

    error "当前 HOME：$REAL_HOME"

    error "为了避免 cron / tmux / 编译目录出现问题，停止部署。"

    exit 1

fi

ok "$OP_USER HOME：$OP_HOME"


# ============================================================
# 确认 op 是普通用户
#
# 不强制修改已有用户的 UID/GID。
# 这里只检查它不是 root。
# ============================================================

OP_UID=$(id -u "$OP_USER")

if [ "$OP_UID" -eq 0 ]; then

    error "$OP_USER 的 UID 为 0。"
    error "$OP_USER 不能是 root 用户。"

    exit 1

fi

ok "$OP_USER UID：$OP_UID（普通用户）"


# ============================================================
# 确认 op 不属于 sudo / wheel
#
# 如果已有用户本来就拥有管理员权限，这里不强制删除，
# 只给出提示。
# ============================================================

OP_GROUPS=$(id -nG "$OP_USER" 2>/dev/null || true)

if echo "$OP_GROUPS" | grep -Eq '(^| )(sudo|wheel)( |$)'; then

    warn "$OP_USER 当前属于 sudo/wheel 管理员组。"
    warn "本脚本不会自动删除现有管理员权限。"

else

    ok "$OP_USER 没有加入 sudo/wheel"

fi


# ============================================================
# 确保 /home/op 所有权正确
#
# 只处理 HOME 本身。
# 不递归修改现有 ImmortalWrt 源码目录。
# ============================================================

chown "$OP_USER:$OP_USER" "$OP_HOME"

ok "$OP_HOME 所有权正常"


# ============================================================
# 安装 APT 软件包
# ============================================================

export DEBIAN_FRONTEND=noninteractive


info "更新 APT 软件包索引..."

apt-get update -y

ok "APT 更新完成"


# ============================================================
# ImmortalWrt 官方 Debian / Ubuntu 编译依赖
#
# 来源：
# ImmortalWrt 官方 README
#
# 当前官方列出的依赖：
#
# ack
# antlr3
# asciidoc
# autoconf
# automake
# autopoint
# binutils
# bison
# build-essential
# bzip2
# ccache
# clang
# cmake
# cpio
# curl
# device-tree-compiler
# ecj
# fastjar
# flex
# gawk
# gettext
# gcc-multilib
# g++-multilib
# git
# gnutls-dev
# gperf
# haveged
# help2man
# intltool
# lib32gcc-s1
# libc6-dev-i386
# libelf-dev
# libglib2.0-dev
# libgmp3-dev
# libltdl-dev
# libmpc-dev
# libmpfr-dev
# libncurses-dev
# libpython3-dev
# libreadline-dev
# libssl-dev
# libtool
# libyaml-dev
# libz-dev
# lld
# llvm
# lrzsz
# mkisofs
# msmtp
# nano
# ninja-build
# p7zip
# p7zip-full
# patch
# pkgconf
# python3
# python3-pip
# python3-ply
# python3-docutils
# python3-pyelftools
# qemu-utils
# re2c
# rsync
# scons
# squashfs-tools
# subversion
# swig
# texinfo
# uglifyjs
# upx-ucl
# unzip
# vim
# wget
# xmlto
# xxd
# zlib1g-dev
# zstd
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
gcc-multilib
g++-multilib
git
gnutls-dev
gperf
haveged
help2man
intltool
lib32gcc-s1
libc6-dev-i386
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
# 本自动编译方案额外需要的程序
#
# tmux：
#   专门用于查看编译过程
#
# cron：
#   每周自动启动编译
#
# util-linux：
#   提供 flock 等工具
# ============================================================

AUTOMATION_PACKAGES="
cron
tmux
util-linux
"


# ============================================================
# 安装依赖
# ============================================================

info "安装 ImmortalWrt 编译依赖..."

apt-get install -y \
    $IMMORTALWRT_PACKAGES \
    $AUTOMATION_PACKAGES

ok "所有 APT 依赖安装完成"


# ============================================================
# 检查并启动 cron
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
    warn "无法自动检查 cron 服务状态。"

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
# 检查 CPU 架构
# ============================================================

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

echo
echo "CPU 架构：$ARCH"


case "$ARCH" in

    amd64)
        ok "CPU 架构为 amd64"
        ;;

    arm64)
        warn "当前 CPU 架构为 arm64。"
        warn "ImmortalWrt 官方主要推荐 AMD64。"
        warn "ARM64 可以尝试编译，但官方不提供兼容性保证。"
        ;;

    *)
        warn "当前 CPU 架构为 $ARCH"
        warn "不是 ImmortalWrt 官方主要推荐的 AMD64。"
        ;;

esac


# ============================================================
# 检查 CPU
# ============================================================

CPU_COUNT=$(nproc)

echo "CPU 核心数：$CPU_COUNT"

if [ "$CPU_COUNT" -lt 2 ]; then

    warn "CPU 少于 2 核，编译速度可能较慢。"

else

    ok "CPU 核心数正常"

fi


# ============================================================
# 检查内存
# ============================================================

MEMORY_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)

MEMORY_GB=$(awk '
BEGIN {
    printf "%.1f", '"$MEMORY_KB"' / 1024 / 1024
}
')


echo "内存：${MEMORY_GB} GiB"


MIN_MEMORY_KB=$((4 * 1024 * 1024))


if [ "$MEMORY_KB" -lt "$MIN_MEMORY_KB" ]; then

    warn "内存低于 ImmortalWrt 官方建议的 4 GiB。"
    warn "当前：${MEMORY_GB} GiB"
    warn "继续部署，但编译可能失败或非常慢。"

else

    ok "内存达到官方建议"

fi


# ============================================================
# 检查磁盘空间
# ============================================================

AVAILABLE_KB=$(df -Pk "$OP_HOME" | awk 'NR==2 {print $4}')

AVAILABLE_GB=$(awk '
BEGIN {
    printf "%.1f", '"$AVAILABLE_KB"' / 1024 / 1024
}
')


echo "可用磁盘空间：${AVAILABLE_GB} GiB"


MIN_DISK_KB=$((25 * 1024 * 1024))


if [ "$AVAILABLE_KB" -lt "$MIN_DISK_KB" ]; then

    error "可用磁盘空间不足 25 GiB。"
    error "当前：${AVAILABLE_GB} GiB"

    exit 1

else

    ok "磁盘空间达到官方建议"

fi


# ============================================================
# 检查 PATH
#
# ImmortalWrt 官方要求：
# PATH 和工作目录不要包含空格或非 ASCII 字符。
# ============================================================

case ":$PATH:" in

    *" "*)
        error "PATH 中存在空格。"
        error "ImmortalWrt 官方要求避免这种情况。"
        exit 1
        ;;

esac


if printf '%s' "$PATH" | LC_ALL=C grep -q '[^ -~]' ; then

    error "PATH 中存在非 ASCII 字符。"
    error "ImmortalWrt 官方要求避免这种情况。"

    exit 1

fi

ok "PATH 检查通过"


# ============================================================
# 检查 ImmortalWrt 源码
#
# 情况：
#
# 1. /home/op/immortalwrt 不存在
#    → op 用户 clone
#
# 2. 目录存在但不是 Git 仓库
#    → 停止，不覆盖
#
# 3. 已经是 Git 仓库
#    → 直接使用
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

    error "为了避免覆盖已有数据，部署停止。"

    exit 1


else

    ok "ImmortalWrt Git 仓库已经存在"

fi


# ============================================================
# 检查源码目录权限
# ============================================================

if ! runuser -u "$OP_USER" -- test -r "$IMMORTALWRT_DIR"; then

    error "$OP_USER 无法读取 $IMMORTALWRT_DIR"

    exit 1

fi


if ! runuser -u "$OP_USER" -- test -w "$IMMORTALWRT_DIR"; then

    error "$OP_USER 无法写入 $IMMORTALWRT_DIR"

    error "请检查现有源码目录权限。"

    exit 1

fi


ok "$OP_USER 可以正常读写 ImmortalWrt 源码目录"


# ============================================================
# 检查 Git remote
# ============================================================

info "检查 ImmortalWrt Git remote..."


REMOTE_URL=$(runuser -u "$OP_USER" -- \
    git -C "$IMMORTALWRT_DIR" remote get-url origin 2>/dev/null || true)


if [ -z "$REMOTE_URL" ]; then

    warn "没有检测到 origin remote。"

else

    echo "origin：$REMOTE_URL"

    ok "Git origin 检查完成"

fi


# ============================================================
# 下载 GitHub 上的三个脚本
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
# 检查 Shell 语法
# ============================================================

info "检查三个 Shell 脚本语法..."


bash -n "$TMP_DIR/weekly-build.sh"

bash -n "$TMP_DIR/weekly-build-run.sh"

bash -n "$TMP_DIR/weekly-build-launcher.sh"


ok "三个脚本 Shell 语法检查通过"


# ============================================================
# 安装脚本
#
# 如果原来存在旧版本：
#   先备份
#
# 不会删除旧文件。
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


ok "三个脚本安装完成"


# ============================================================
# 再次检查脚本权限
# ============================================================

if [ ! -x "$BUILD_SCRIPT" ]; then
    error "$BUILD_SCRIPT 不可执行"
    exit 1
fi

if [ ! -x "$RUN_SCRIPT" ]; then
    error "$RUN_SCRIPT 不可执行"
    exit 1
fi

if [ ! -x "$LAUNCHER_SCRIPT" ]; then
    error "$LAUNCHER_SCRIPT 不可执行"
    exit 1
fi


ok "三个脚本均可执行"


# ============================================================
# 检查脚本所有者
# ============================================================

for FILE in \
    "$BUILD_SCRIPT" \
    "$RUN_SCRIPT" \
    "$LAUNCHER_SCRIPT"
do

    OWNER=$(stat -c '%U:%G' "$FILE")

    if [ "$OWNER" != "$OP_USER:$OP_USER" ]; then

        error "$FILE 所有者错误：$OWNER"

        exit 1

    fi

done


ok "三个脚本所有者均为 op:op"


# ============================================================
# 配置 op 用户 crontab
#
# 只删除本脚本之前管理的那一条任务。
#
# 不影响 op 用户其他 cron。
# ============================================================

info "配置 $OP_USER 用户 crontab..."


CURRENT_CRONTAB=$(crontab -u "$OP_USER" -l 2>/dev/null || true)


NEW_CRONTAB=$(
    printf '%s\n' "$CURRENT_CRONTAB" \
    | grep -vF "$CRON_MARK" \
    | grep -vF "$LAUNCHER_SCRIPT" \
    || true
)


# 删除连续空行
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
# 检查 crontab
# ============================================================

echo
echo "============================================================"
echo "$OP_USER 当前 crontab"
echo "============================================================"

crontab -u "$OP_USER" -l


# ============================================================
# 检查 tmux 是否可以由 op 正常运行
#
# 这里不创建正式的 op session。
# 只测试 tmux 本身。
# ============================================================

info "测试 op 用户 tmux..."


runuser -u "$OP_USER" -- \
    tmux -V


# ============================================================
# 检查 op 用户能够执行 launcher
#
# 只进行 Shell 语法和权限测试。
# 不在部署过程中启动编译。
# ============================================================

info "检查 op 用户编译脚本..."


runuser -u "$OP_USER" -- \
    bash -n "$BUILD_SCRIPT"

runuser -u "$OP_USER" -- \
    bash -n "$RUN_SCRIPT"

runuser -u "$OP_USER" -- \
    bash -n "$LAUNCHER_SCRIPT"


ok "op 用户脚本检查通过"


# ============================================================
# 最终显示
# ============================================================

echo
echo
echo "============================================================"
echo "                 ImmortalWrt 自动编译部署完成"
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
echo "tmux："
echo "  $OP_USER 的专用 session：op"

echo
echo "定时任务："
echo "  每周日 03:00"

echo
echo "cron："
echo "  $CRON_SCHEDULE $LAUNCHER_SCRIPT"

echo
echo "============================================================"
echo "手动立即启动一次编译："
echo
echo "  sudo -u op $LAUNCHER_SCRIPT"
echo
echo "============================================================"

echo
echo "查看编译过程："
echo
echo "  sudo -u op tmux attach-session -t op"
echo
echo "============================================================"

echo
echo "如果你已经切换到 op 用户，则直接："
echo
echo "  ~/weekly-build-launcher.sh"
echo
echo "  tmux attach-session -t op"
echo
echo "============================================================"

echo
echo "部署没有启动编译。"
echo "第一次编译需要手动启动，或者等待下一次 cron。"
echo
