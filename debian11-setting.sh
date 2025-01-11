#!/bin/bash

# 检查是否以 root 用户运行
if [[ $EUID -ne 0 ]]; then
   echo "请以 root 用户运行此脚本。"
   exit 1
fi

# 修改 SSH 配置
echo "配置 SSH 设置..."
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config

# 重启 SSH 服务
echo "重启 SSH 服务..."
service ssh restart

# 提示用户设置 root 密码
echo "请为 root 用户设置新密码："
passwd root

# 配置系统语言为简体中文
echo "配置系统语言为简体中文..."
sed -i 's/^# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=zh_CN.UTF-8

# 设置时区为香港
echo "设置系统时区为香港..."
timedatectl set-timezone Asia/Hong_Kong

# 确认设置完成
echo "所有设置已完成！请重新登录以应用语言设置。"
