#!/bin/bash

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 用户运行此脚本。"
  exit 1
fi

# 启用 root 用户 SSH 登录和密码认证
echo "配置 SSH 以允许 root 登录和密码认证..."
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
service ssh restart
echo "SSH 配置已更新并重启服务。"

# 设置 root 用户密码
echo "请设置 root 用户密码："
passwd

# 安装中文语言包
echo "安装中文语言包..."
apt update
apt install -y locales
sed -i "s/^# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/" /etc/locale.gen
locale-gen
update-locale LANG=zh_CN.UTF-8
echo "系统语言已设置为简体中文 (zh_CN.UTF-8)。"

# 设置时区为香港
echo "设置时区为香港..."
timedatectl set-timezone Asia/Hong_Kong
echo "时区已设置为香港 (Asia/Hong_Kong)。"

# 确认操作完成
echo "操作已完成，请重新登录验证配置是否生效。"
