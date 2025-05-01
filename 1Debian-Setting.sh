#!/bin/bash
set -e

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 权限运行此脚本（使用 sudo）"
  exit 1
fi

# 检查命令存在
check_command() {
  command -v "$1" >/dev/null 2>&1
}

# 自动安装依赖包
install_package() {
  local pkg=$1
  echo "安装依赖项：$pkg..."
  if check_command apt; then
    apt update && apt install -y "$pkg"
  elif check_command dnf; then
    dnf install -y "$pkg"
  elif check_command yum; then
    yum install -y "$pkg"
  else
    echo "不支持的包管理器，请手动安装 $pkg"
    exit 1
  fi
}

# 确保必要依赖存在
ensure_dependencies() {
  echo "检查并安装依赖..."

  ! check_command locale-gen && ! check_command localedef && install_package locales
  ! check_command timedatectl && install_package systemd
  ! check_command curl && install_package curl
  ! check_command passwd && install_package passwd
  ! check_command ss && install_package iproute2

  echo "依赖检查完成"
}

# 设置系统语言
change_locale() {
  echo "选择系统语言:"
  echo "1) 英语 (en_US.UTF-8)"
  echo "2) 简体中文 (zh_CN.UTF-8)"
  echo "3) 繁体中文 (zh_TW.UTF-8)"
  read -p "请输入选项 [1-3]: " locale_choice

  case $locale_choice in
    1) locale="en_US.UTF-8" ;;
    2) locale="zh_CN.UTF-8" ;;
    3) locale="zh_TW.UTF-8" ;;
    *) echo "无效选择"; return ;;
  esac

  echo "设置语言为 $locale..."

  if check_command apt; then
    install_package locales
    grep -q "^${locale}" /etc/locale.gen || echo "${locale} UTF-8" >> /etc/locale.gen
    locale-gen
    update-locale LANG=$locale
    echo "LANG=$locale" > /etc/default/locale
  elif check_command dnf || check_command yum; then
    pkgname="glibc-langpack-${locale%%_*}"
    install_package "$pkgname"
    if [ -d "/usr/share/i18n/locales" ] && [ -d "/usr/share/i18n/charmaps" ]; then
      localedef -c -i "${locale%%.*}" -f UTF-8 "$locale" || true
    else
      echo "[警告] 缺少 i18n 路径，跳过 localedef"
    fi
    echo "LANG=$locale" | tee /etc/locale.conf >/dev/null
  else
    echo "[错误] 无法识别系统环境，请手动配置 locale"
    return
  fi

  echo "语言设置完成为 $locale"
}

# 设置系统时区
change_timezone() {
  echo "选择时区:"
  echo "1) 台北"
  echo "2) 香港"
  echo "3) 新加坡"
  echo "4) 自动获取（基于公网 IP）"
  read -p "请输入选项 [1-4]: " tz_choice

  case $tz_choice in
    1) timezone="Asia/Taipei" ;;
    2) timezone="Asia/Hong_Kong" ;;
    3) timezone="Asia/Singapore" ;;
    4)
      if check_command curl; then
        timezone=$(curl -s https://ipapi.co/timezone)
        echo "自动检测到时区：$timezone"
      else
        echo "无法使用 curl 自动检测，请先安装 curl"; return
      fi
      ;;
    *) echo "无效选择"; return ;;
  esac

  timedatectl set-timezone "$timezone"
  echo "已设置时区为 $timezone"
}

# 修改 SSH 密码
change_ssh_password() {
  read -p "请输入要修改密码的用户名: " username
  if id "$username" &>/dev/null; then
    passwd "$username"
    echo "密码已修改"
  else
    echo "用户 $username 不存在"
  fi
}

# 启用 root 登录
enable_root_login() {
  echo "启用 root 密码登录..."
  passwd root
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
  systemctl restart ssh || systemctl restart sshd
  echo "已启用 root 密码登录并重启 SSH 服务"
}

# 修改 SSH 端口
