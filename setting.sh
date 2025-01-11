#!/bin/bash

# 检查是否以 root 身份运行
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 身份运行此脚本。"
    exit 1
fi

# 提示用户输入新密码
read -sp "请输入新密码: " password
echo
read -sp "请再次输入新密码: " password_confirm
echo

# 验证两次输入的密码是否一致
if [[ "$password" != "$password_confirm" ]]; then
    echo "两次输入的密码不一致，脚本退出。"
    exit 1
fi

# 修改 SSH 配置文件
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config

# 重启 SSH 服务
service ssh restart

# 更新 root 用户密码
echo -e "root:$password" | chpasswd

echo "配置已完成，root 用户密码已更新。"
