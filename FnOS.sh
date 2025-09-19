#!/bin/bash

# =============================
# 可管理服务清单（示例）
# =============================
declare -A SERVICES
SERVICES[avahi-daemon]="局域网服务发现 (Bonjour/zeroconf)，用于Mac/iOS发现NAS"
SERVICES[sshd]="SSH 远程登录管理 (建议保留，如不用远程可关闭)"
SERVICES[smbd]="Samba 文件共享 (Windows/Mac 访问NAS)"
SERVICES[nmbd]="Samba NetBIOS 名称解析 (多数情况下可关闭)"
SERVICES[nfs-server]="NFS 文件共享 (Linux/Unix 访问NAS)"
SERVICES[cupsd]="打印服务 (NAS 共享打印机时使用)"
SERVICES[saned]="扫描仪服务 (USB/网络扫描仪共享)"
SERVICES[minidlna]="DLNA 媒体服务器 (电视/播放器访问NAS视频)"
SERVICES[plexmediaserver]="Plex 媒体中心"
SERVICES[transmission-daemon]="BT/磁力下载服务"
SERVICES[docker]="容器服务 (运行额外应用时需要)"

# =============================
# 功能函数
# =============================
list_services() {
    echo "===== 可管理服务列表 ====="
    i=1
    for svc in "${!SERVICES[@]}"; do
        systemctl is-enabled "$svc" &>/dev/null && enabled="已启用" || enabled="已禁用"
        systemctl is-active "$svc" &>/dev/null && active="运行中" || active="已停止"
        printf "%2d) %-20s %-6s %-6s → %s\n" "$i" "$svc" "$enabled" "$active" "${SERVICES[$svc]}"
        INDEX[$i]="$svc"
        ((i++))
    done
    echo "==========================="
}

toggle_service() {
    svc=$1
    echo "选择操作: 1) 开启 2) 关闭 3) 查看状态"
    read -rp "> " choice
    case $choice in
        1)
            systemctl enable --now "$svc"
            echo "[+] 服务 $svc 已永久开启"
            ;;
        2)
            systemctl disable --now "$svc"
            systemctl mask "$svc" 2>/dev/null
            echo "[-] 服务 $svc 已永久关闭"
            ;;
        3)
            systemctl status "$svc" --no-pager
            ;;
        *)
            echo "[!] 无效选项"
            ;;
    esac
}

# =============================
# 主菜单（数字选项）
# =============================
while true; do
    list_services
    echo "输入服务序号操作，或输入 0 退出"
    read -rp "> " num
    [[ "$num" == "0" ]] && break
    if [[ -n "${INDEX[$num]}" ]]; then
        toggle_service "${INDEX[$num]}"
    else
        echo "[!] 序号无效"
    fi
done
