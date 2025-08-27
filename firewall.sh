#!/bin/bash
# 防火墙交互管理脚本 - 最终完整版

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"

[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行${RESET}" && exit 1

pause() { read -r -p "按回车返回上级菜单..." _; }

# ===== 安装/启用 UFW =====
ensure_ufw() {
  command -v ufw >/dev/null 2>&1 || { echo -e "${YELLOW}未检测到 UFW，正在安装...${RESET}"; apt-get update -y && apt-get install -y ufw; }
  IPV6_STATE=$(grep -E '^IPV6=' /etc/default/ufw 2>/dev/null | awk -F= '{print $2}')
  [[ -z "$IPV6_STATE" ]] && IPV6_STATE="yes"
  ufw status | grep -qi "inactive" && ufw --force enable
}

# ===== SSH 防断连 =====
ensure_ssh_safe() {
  read -r -p "请输入当前 SSH 端口（默认 22）: " SSH_PORT
  SSH_PORT=${SSH_PORT:-22}
  [[ ! $SSH_PORT =~ ^[0-9]{1,5}$ ]] && echo -e "${RED}端口无效${RESET}" && exit 1
  ufw status | grep -qE "ALLOW.*\b${SSH_PORT}/tcp\b" || ufw allow "${SSH_PORT}/tcp"
}

# ===== 解析端口文本 =====
normalize_and_validate_ports() {
  local raw="$1"; raw="${raw//,/ }" && raw=$(echo "$raw" | xargs)
  local tokens=(); local t
  for t in $raw; do
    if [[ "$t" =~ ^([0-9]{1,5})[[:space:]]*[:-][[:space:]]*([0-9]{1,5})$ ]]; then
      local a="${BASH_REMATCH[1]}"; local b="${BASH_REMATCH[2]}"
      [[ $a -ge 1 && $a -le 65535 && $b -ge 1 && $b -le 65535 && $a -le $b ]] || { echo -e "${RED}无效端口范围：$t${RESET}"; return 1; }
      tokens+=("${a}:${b}")
    elif [[ "$t" =~ ^[0-9]{1,5}$ ]]; then
      [[ $t -ge 1 && $t -le 65535 ]] || { echo -e "${RED}无效端口：$t${RESET}"; return 1; }
      tokens+=("$t")
    else
      echo -e "${RED}无法识别端口/范围：$t${RESET}"; return 1
    fi
  done
  PORT_TOKENS=("${tokens[@]}")
  return 0
}

# ===== 状态展示 =====
status_summary() {
  local icmp="未明确"
  ufw status verbose | grep -qE "ALLOW IN.*icmp" && icmp="允许"
  local outpol=$(ufw status verbose | awk -F: '/Default:/{print $2}' | xargs)
  [[ -z "$outpol" ]] && outpol="未知"
  echo -e "\n${CYAN}${BOLD}—— 当前状态 ——${RESET}"
  echo -e "IPv6 开关：${BOLD}${IPV6_STATE}${RESET}"
  echo -e "入站 SSH：${BOLD}$(ufw status | awk '/ALLOW/ && /\/tcp/ && $1 ~ /^[0-9]+$/ {print $1"/tcp"}' | paste -sd',' - || echo 无)${RESET}"
  echo -e "入站 TCP：${BOLD}$(ufw status | awk '/ALLOW/ && /\/tcp/{print $1}' | sed 's#/tcp##' | grep -v "^${SSH_PORT}$" | paste -sd',' - || echo 无)${RESET}"
  echo -e "入站 UDP：${BOLD}$(ufw status | awk '/ALLOW/ && /\/udp/{print $1}' | paste -sd',' - || echo 无)${RESET}"
  echo -e "入站 ICMP：${BOLD}${icmp}${RESET}"
  echo -e "出站策略：${BOLD}${outpol}${RESET}"
}

# ===== 放行端口 =====
allow_tokens() {
  local proto="$1"; shift
  ensure_ssh_safe
  for tok in "$@"; do
    if [[ "$tok" =~ : ]]; then
      start=${tok%%:*}; end=${tok##*:}
      skip_all=true
      for ((p=start;p<=end;p++)); do
        if ! ufw status | grep -qE "ALLOW.*\b${p}/${proto}\b"; then
          skip_all=false
          ufw allow "${start}:${end}/${proto}" && echo -e "${GREEN}放行 ${start}:${end}/${proto}${RESET}"
          break
        fi
      done
      $skip_all && echo -e "${YELLOW}${tok}/${proto} 已存在，跳过${RESET}"
    else
      ufw status | grep -qE "ALLOW.*\b${tok}/${proto}\b" && echo -e "${YELLOW}${tok}/${proto} 已存在，跳过${RESET}" || ufw allow "${tok}/${proto}" && echo -e "${GREEN}放行 ${tok}/${proto}${RESET}"
    fi
  done
}

# ===== 删除规则 =====
delete_by_numbered() {
  ensure_ssh_safe
  ufw status numbered
  read -r -p "输入要删除的编号（空返回）： " ids
  [[ -z "$ids" ]] && return
  ids_sorted=$(echo "$ids" | xargs -n1 | sort -nr)
  while read -r id; do ufw --force delete "$id"; done <<< "$ids_sorted"
}

# ===== 批量导入/导出 =====
import_ports() {
  ensure_ssh_safe
  read -r -p "输入文件路径: " file
  [[ ! -f "$file" ]] && echo -e "${RED}文件不存在${RESET}" && return
  read -r -p "协议 (tcp/udp): " proto
  [[ "$proto" != "tcp" && "$proto" != "udp" ]] && echo -e "${RED}协议错误${RESET}" && return
  while read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    normalize_and_validate_ports "$line" || continue
    allow_tokens "$proto" "${PORT_TOKENS[@]}"
  done < "$file"
}

export_ports() {
  ensure_ssh_safe
  read -r -p "输出文件路径: " outfile
  echo "# SSH 端口" > "$outfile"
  ufw status | awk '/ALLOW/ && /\/tcp/ && $1 ~ /^[0-9]+$/ {print $1}' >> "$outfile"
  echo "# TCP 端口" >> "$outfile"
  ufw status | awk '/ALLOW/ && /\/tcp/{print $1}' | sed 's#/tcp##' >> "$outfile"
  echo "# UDP 端口" >> "$outfile"
  ufw status | awk '/ALLOW/ && /\/udp/{print $1}' | sed 's#/udp##' >> "$outfile"
  echo "# ICMP" >> "$outfile"
  ufw status | grep -qE "ALLOW IN.*icmp" && echo "允许" >> "$outfile" || echo "未允许" >> "$outfile"
  echo -e "${GREEN}导出完成：$outfile${RESET}"
}

# ===== 子菜单 =====
menu_ssh() { read -r -p "输入要放行的 SSH 端口（空返回）： " p; [[ -n "$p" ]] && normalize_and_validate_ports "$p" && allow_tokens tcp "${PORT_TOKENS[@]}"; pause; }
menu_tcp() { read -r -p "输入要放行 TCP 端口或范围： " p; [[ -n "$p" ]] && normalize_and_validate_ports "$p" && allow_tokens tcp "${PORT_TOKENS[@]}"; pause; }
menu_udp() { read -r -p "输入要放行 UDP 端口或范围： " p; [[ -n "$p" ]] && normalize_and_validate_ports "$p" && allow_tokens udp "${PORT_TOKENS[@]}"; pause; }
menu_icmp() { 
  if ufw status | grep -qE "ALLOW IN.*icmp"; then
    echo -e "${YELLOW}ICMP 已放行${RESET}"
  else
    ufw allow in proto icmp && echo -e "${GREEN}ICMP 已放行${RESET}"
  fi
  pause
}
menu_outbound() { read -r -p "允许所有出站？(y/n): " x; [[ "$x" =~ ^[Yy]$ ]] && ufw default allow outgoing || ufw default deny outgoing; pause; }

# ===== 主菜单 =====
main_menu() {
  while true; do
    clear
    status_summary
    echo -e "\n${CYAN}${BOLD}—— 防火墙管理菜单 ——${RESET}"
    echo "1) 入站 SSH"
    echo "2) 入站 TCP"
    echo "3) 入站 UDP"
    echo "4) 入站 ICMP"
    echo "5) 出站规则"
    echo "6) 批量导入端口"
    echo "7) 批量导出端口"
    echo "0) 退出并应用"
    read -r -p "选择: " op
    case "$op" in
      1) menu_ssh ;;
      2) menu_tcp ;;
      3) menu_udp ;;
      4) menu_icmp ;;
      5) menu_outbound ;;
      6) import_ports ;;
      7) export_ports ;;
      0) ufw reload; echo -e "${GREEN}防火墙规则已应用${RESET}"; exit 0 ;;
      *) echo -e "${RED}无效选项${RESET}"; pause ;;
    esac
  done
}

# ===== 初始化 =====
ensure_ufw
ensure_ssh_safe
main_menu
