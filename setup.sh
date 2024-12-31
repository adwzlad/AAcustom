#!/bin/bash

# 检查是否以 root 用户运行
if [[ $EUID -ne 0 ]]; then
   echo "请以 root 用户运行此脚本。" 
   exit 1
fi

# 修改 SSH 配置，允许 root 登录并启用密码认证
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
service sshd restart

# 交互式设置 root 用户密码
echo "请输入 root 用户的新密码："
read -s root_password
echo "请再次输入 root 用户的新密码："
read -s root_password_confirm

# 验证两次输入是否一致
if [[ "$root_password" != "$root_password_confirm" ]]; then
    echo "两次输入的密码不一致，请重新运行脚本设置密码。"
    exit 1
fi

# 设置 root 用户密码
echo "root:$root_password" | chpasswd
echo "root 密码已成功更新。"

# 安装中文语言包
apt update && apt install -y locales
sed -i "s/^# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/" /etc/locale.gen
locale-gen
update-locale LANG=zh_CN.UTF-8

# 设置时区为 Asia/Hong_Kong
ln -sf /usr/share/zoneinfo/Asia/Hong_Kong /etc/localtime
timedatectl set-timezone Asia/Hong_Kong

# 重启系统
echo "系统配置完成，系统将重启以应用更改..."
reboot
