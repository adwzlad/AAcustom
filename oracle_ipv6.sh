#!/bin/bash
# 彻底撤销 auto_ipv6 脚本的所有修改

echo "[1] 删除 /usr/local/bin/auto_ipv6.sh..."
rm -f /usr/local/bin/auto_ipv6.sh

echo "[2] 禁用并删除 systemd 服务 auto-ipv6.service..."
systemctl disable auto-ipv6.service --now 2>/dev/null
rm -f /etc/systemd/system/auto-ipv6.service
systemctl daemon-reload

echo "[3] 删除 cron 定时任务..."
crontab -l 2>/dev/null | grep -v "auto_ipv6.sh" | crontab -

echo "[4] 可选：删除 /root/oracle_ipv6（仅当你不再需要）"
# rm -f /root/oracle_ipv6

echo "[完成] 所有由此脚本创建的内容均已移除。"
