#!/bin/bash
set -e

function check_command() {
  command -v "$1" >/dev/null 2>&1
}

function install_package() {
  local pkg=$1
  echo "尝试安装缺失组件：$pkg..."

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

function ensure_dependencies() {
  echo "检查并安装依赖..."

  if ! check_command locale-gen && ! check_command localedef; then
    echo "缺少 locale 相关工具"
    install_package locales || install_package glibc-common
  fi

  if ! check_command timedatectl; then
    echo "缺少 timedatectl"
    install_package systemd
  fi

  if ! check_command curl; then
    install_package curl
  fi

  if ! check_command passwd; then
    echo "缺少 passwd 命令"
    install_package passwd
  fi

  echo "依赖检查完成"
}

function change_locale() {
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
  if check_command locale-gen; then
    sed -i "s/^LANG=.*/LANG=$locale/" /etc/default/locale || echo "LANG=$locale" > /etc/default/locale
    locale-gen "$locale"
    update-locale LANG="$locale"
  elif check_command localedef; then
    localedef -v -c -i "${locale%%.*}" -f UTF-8 "$locale" || true
    echo "LANG=$locale" > /etc/locale.conf
  fi
  echo "语言修改完成"
}

function change_timezone() {
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
        echo "检测到的时区为 $timezone"
      else
        echo "无法使用 curl 自动检测，请手动安装 curl 或选择其他选项"; return
      fi
      ;;
    *) echo "无效选择"; return ;;
  esac

  timedatectl set-timezone "$timezone"
  echo "时区已设置为 $timezone"
}

function change_ssh_password() {
  read -p "请输入要修改密码的用户名: " username
  if id "$username" &>/dev/null; then
    passwd "$username"
    echo "密码已修改"
  else
    echo "用户 $username 不存在"
  fi
}

function enable_root_login() {
  echo "启用 root 密码登录..."
  passwd root
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  echo "已启用 root 密码登录并重启 SSH 服务"
}

function main_menu() {
  ensure_dependencies

  while true; do
    echo ""
    echo "==== 系统配置菜单 ===="
    echo "1) 修改系统语言"
    echo "2) 修改系统时区"
    echo "3) 修改指定账户SSH密码"
    echo "4) 启用ROOT密码登录"
    echo "0) 退出"
    read -p "请选择操作 [0-4]: " opt

    case $opt in
      1) change_locale ;;
      2) change_timezone ;;
      3) change_ssh_password ;;
      4) enable_root_login ;;
      0) echo "退出脚本"; break ;;
      *) echo "无效选项" ;;
    esac
  done
}

main_menu
