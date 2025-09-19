#!/bin/bash
# FnOS NAS 服务管理脚本 (简化版: 开启=永久开启, 关闭=永久关闭)

GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

# 服务说明
declare -A SERVICE_DESC=(
  [sshd]="必需 → SSH 远程管理服务（用于远程登录 NAS，强烈建议保留）"
  [smbd]="必需 → Samba 文件共享服务（Windows/macOS/Linux 访问 NAS 文件）"
  [nmbd]="必需 → NetBIOS 名称解析（Samba 依赖，用于局域网发现）"
  [nfs-server]="必需 → NFS 文件共享服务（Linux/虚拟机常用）"
  [rpcbind]="必需 → NFS 依赖服务（RPC 调用端口管理）"
  [cron]="必需 → 定时任务调度器（NAS 计划任务/备份必需）"
  [mdadm]="必需 → Linux 软件 RAID 管理（RAID 阵列监控与管理）"
  [lvm2-lvmetad]="必需 → LVM 逻辑卷管理守护进程"

  [afpd]="可选 → Apple AFP 文件共享（老款 macOS 使用，现代已被 SMB 替代）"
  [vsftpd]="可选 → FTP 文件传输服务（一般只在需要 FTP 共享时开启）"
  [rsync]="可选 → Rsync 文件同步服务（远程/本地数据备份常用）"
  [webdav]="可选 → WebDAV 网络文件挂载（通过 HTTP 共享文件）"

  [minidlnad]="可关闭 → DLNA 媒体共享服务（电视/播放器访问 NAS 视频）"
  [plexmediaserver]="可关闭 → Plex 多媒体服务（流媒体播放，不需要可关）"
  [jellyfin]="可关闭 → Jellyfin 开源流媒体（影音服务器，非存储核心功能）"
  [photo_station]="可关闭 → NAS 自带相册管理（占用 CPU/内存，可关）"
  [video_station]="可关闭 → NAS 自带视频管理（仅用于在线观看）"

  [syncthing]="可选 → P2P 文件同步（多设备间数据同步）"
  [tailscaled]="可选 → Tailscale VPN 客户端（远程访问 NAS）"
  [zerotier-one]="可选 → ZeroTier 虚拟组网（远程访问 NAS）"

  [fail2ban]="可选 → 防暴力破解工具（保护 SSH/FTP 登录安全）"
  [firewalld]="可选 → 防火墙服务（网络访问控制）"
  [clamav-daemon]="可关闭 → 病毒扫描服务（性能消耗大，NAS 一般不需要）"
  [suricata]="可关闭 → 入侵检测系统（IDS/IPS，家庭环境基本用不到）"

  [cups]="可关闭 → 打印服务（NAS 共享打印机时用，不用可关）"
  [avahi-daemon]="可关闭 → Bonjour 服务（Apple 设备发现 NAS，可关）"
  [bluetooth]="可关闭 → 蓝牙支持（NAS 很少需要）"
  [upsd]="可选 → UPS 电源管理（连接不间断电源时才需要）"

  [docker]="可选 → Docker 容器服务（NAS 跑容器时才需要）"
  [containerd]="可选 → 容器运行时（Docker 依赖）"
)

# 获取所有服务列表
get_services() {
  systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}' | sed 's/\.service//'
}

# 显示服务状态和分类
show_services() {
  echo -e "${CYAN}=== FnOS 服务分类与状态 ===${RESET}"
  for svc in $(get_services); do
    state=$(systemctl is-active $svc 2>/dev/null)
    enabled=$(systemctl is-enabled $svc 2>/dev/null)
    desc=${SERVICE_DESC[$svc]:-"未知 → 未分类服务（可能是系统内部服务）"}

    case "$desc" in
      必需*) color=$GREEN ;;
      可选*) color=$YELLOW ;;
      可关闭*) color=$RED ;;
      *) color=$CYAN ;;
    esac

    echo -e "$color[$svc]${RESET} 状态: $state | 开机: $enabled"
    echo -e "    ➜ $desc"
  done
}

# 管理服务
manage_service() {
  read -p "请输入要操作的服务名: " svc
  if ! systemctl status $svc &>/dev/null; then
    echo -e "${RED}服务 $svc 不存在！${RESET}"
    return
  fi

  echo "选择操作: "
  echo "1) 永久开启 (启动 + 开机自启)"
  echo "2) 永久关闭 (停止 + 禁止开机自启)"
  echo "3) 返回"
  read -p "输入编号: " choice

  case $choice in
    1) sudo systemctl enable --now $svc && echo -e "${GREEN}已永久开启 $svc${RESET}";;
    2) sudo systemctl disable --now $svc && echo -e "${RED}已永久关闭 $svc${RESET}";;
    *) echo "返回菜单";;
  esac
}

# 主循环
while true; do
  show_services
  echo
  echo "操作菜单:"
  echo "1) 管理某个服务"
  echo "0) 退出"
  read -p "请输入选择: " opt
  case $opt in
    1) manage_service ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
done
