#!/bin/bash
#完整移除snapd，阻止apt自动回装
set -e
#删除全部已安装snap应用
for p in $(snap list 2>/dev/null | awk 'NR>1 {print $1}'); do snap remove --purge "$p"; done
#停止屏蔽服务
systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null
systemctl mask snapd.service snapd.socket snapd.seeded.service 2>/dev/null
#卸载deb包
apt purge -y snapd
apt autoremove --purge -y
#卸载loop挂载
for m in $(mount | grep /snap | awk '{print $3}'); do umount -l "$m" 2>/dev/null; done
#清理目录
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
rm -rf ~/snap
#写入屏蔽，防止apt自动装回snapd
cat > /etc/apt/preferences.d/no-snapd.pref <<'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
apt update
echo "snapd移除完成"
