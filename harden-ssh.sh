#!/usr/bin/env bash
set -euo pipefail

# ============================================
# VPS SSH Hardening Script (No UFW) - A+B
# - Interactive (default) or non-interactive via env vars
# - Adds:
#   (1) Pre-change summary + sshd_config diff preview
#   (2) Post-change ready-to-copy SSH command output
#   (3) Port conflict detection (ss/netstat)
# ============================================

# --------- Defaults (can be overridden by env) ----------
DEFAULT_PORT="${DEFAULT_PORT:-2222}"
DEFAULT_DISABLE_PASSWORD="${DEFAULT_DISABLE_PASSWORD:-yes}"   # yes/no
DEFAULT_ENABLE_FAIL2BAN="${DEFAULT_ENABLE_FAIL2BAN:-yes}"     # yes/no
DEFAULT_FAIL2BAN_MAXRETRY="${DEFAULT_FAIL2BAN_MAXRETRY:-3}"
DEFAULT_FAIL2BAN_FINDTIME="${DEFAULT_FAIL2BAN_FINDTIME:-10m}"
DEFAULT_FAIL2BAN_BANTIME="${DEFAULT_FAIL2BAN_BANTIME:-24h}"
DEFAULT_ALLOW_USERS="${DEFAULT_ALLOW_USERS:-}"               # e.g. "ubuntu,debian,root" (comma separated)
DEFAULT_INTERACTIVE="${DEFAULT_INTERACTIVE:-yes}"            # yes/no
# --------------------------------------------------------

SSHD_CONFIG="/etc/ssh/sshd_config"
TS="$(date +%Y%m%d_%H%M%S)"
TMP_DIR="/tmp/harden-ssh"
mkdir -p "$TMP_DIR"

log() { echo -e "[+] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
err() { echo -e "[ERR] $*" >&2; }
die() { err "$*"; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }
is_systemd() { have_cmd systemctl; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    die "请用 root 运行：sudo bash $0"
  fi
}

service_restart_sshd() {
  if ! is_systemd; then
    die "当前系统没有 systemd（找不到 systemctl），此脚本暂不支持。"
  fi
  if systemctl list-unit-files | grep -q '^sshd\.service'; then
    systemctl restart sshd
  elif systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl restart ssh
  else
    systemctl restart sshd || systemctl restart ssh
  fi
}

detect_default_user() {
  local u="${SUDO_USER:-root}"
  echo "$u"
}

get_home_of_user() {
  local u="$1"
  if have_cmd getent; then
    getent passwd "$u" | awk -F: '{print $6}'
  else
    if [[ "$u" == "root" ]]; then echo "/root"; else echo "/home/$u"; fi
  fi
}

authorized_keys_exists_for_user() {
  local u="$1"
  local h; h="$(get_home_of_user "$u")"
  [[ -f "$h/.ssh/authorized_keys" ]] && [[ -s "$h/.ssh/authorized_keys" ]]
}

prompt() {
  local var_name="$1"
  local question="$2"
  local default="$3"
  local input=""
  read -r -p "$question [$default]: " input || true
  input="${input:-$default}"
  printf -v "$var_name" '%s' "$input"
}

prompt_yesno() {
  local var_name="$1"
  local question="$2"
  local default="$3" # yes/no
  local input=""
  while true; do
    read -r -p "$question (yes/no) [$default]: " input || true
    input="${input:-$default}"
    case "$input" in
      yes|no) printf -v "$var_name" '%s' "$input"; return 0;;
      *) echo "请输入 yes 或 no";;
    esac
  done
}

validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  (( p >= 1 && p <= 65535 )) || return 1
  return 0
}

# ---- Port conflict detection ----
port_in_use() {
  local p="$1"
  # Return 0 if in use, 1 if free, 2 if unknown (no tools)
  if have_cmd ss; then
    # Check listening tcp sockets on any address (IPv4/IPv6)
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${p}\$"; then
      return 0
    else
      return 1
    fi
  elif have_cmd netstat; then
    if netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${p}\$"; then
      return 0
    else
      return 1
    fi
  else
    return 2
  fi
}

ensure_port_free_or_handle() {
  local p="$1"
  local interactive="$2"

  local r=0
  if port_in_use "$p"; then
    r=0
  else
    r=$?
  fi

  if [[ $r -eq 1 ]]; then
    return 0 # free
  elif [[ $r -eq 0 ]]; then
    if [[ "$interactive" == "yes" ]]; then
      warn "端口 ${p} 已被占用（已有服务在监听）。请换一个端口。"
      return 1
    else
      die "端口 ${p} 已被占用（已有服务在监听）。请更换 NEW_PORT 后重试。"
    fi
  else
    # unknown
    warn "无法检测端口占用情况（系统没有 ss 或 netstat）。"
    warn "建议安装：Ubuntu/Debian -> apt install -y iproute2；CentOS/Rocky -> dnf install -y iproute"
    # Continue, but warn user
    return 0
  fi
}
# -------------------------------

backup_file() {
  local f="$1"
  cp -a "$f" "${f}.bak.${TS}"
  log "已备份 $f -> ${f}.bak.${TS}"
}

set_sshd_kv() {
  local key="$1"
  local value="$2"
  if grep -Eiq "^[#[:space:]]*${key}[[:space:]]+" "$SSHD_CONFIG"; then
    sed -ri "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|I" "$SSHD_CONFIG"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}

remove_sshd_kv() {
  local key="$1"
  if grep -Ei "^[[:space:]]*${key}[[:space:]]+" "$SSHD_CONFIG" >/dev/null 2>&1; then
    sed -ri "s|^[[:space:]]*(${key}[[:space:]].*)|# \1|I" "$SSHD_CONFIG"
  fi
}

normalize_allowusers() {
  local s="$1"
  s="${s//,/ }"
  echo "$s" | awk '{$1=$1;print}'
}

print_plan_summary() {
  local login_user="$1"
  local new_port="$2"
  local disable_password="$3"
  local allow_users="$4"
  local enable_fail2ban="$5"
  local f2b_maxretry="$6"
  local f2b_findtime="$7"
  local f2b_bantime="$8"

  echo
  echo "========== 变更摘要（即将应用）=========="
  echo "目标用户（用于给你生成 SSH 命令）: ${login_user}"
  echo "SSH 端口: 22  ->  ${new_port}"
  echo "密码登录: $( [[ "$disable_password" == "yes" ]] && echo "禁用（仅密钥）" || echo "保留（允许密码）" )"
  if [[ -n "$allow_users" ]]; then
    echo "AllowUsers: ${allow_users}"
  else
    echo "AllowUsers: 未设置（不限制）"
  fi
  if [[ "$enable_fail2ban" == "yes" ]]; then
    echo "Fail2Ban: 启用"
    echo "  - maxretry: ${f2b_maxretry}"
    echo "  - findtime: ${f2b_findtime}"
    echo "  - bantime : ${f2b_bantime}"
    echo "  - sshd port: ${new_port}"
  else
    echo "Fail2Ban: 不启用"
  fi
  echo "========================================"
  echo
}

diff_preview_if_possible() {
  local before_file="$1"
  local after_file="$2"
  local interactive="$3"

  if ! have_cmd diff; then
    warn "系统没有 diff 命令，跳过配置差异预览。"
    return 0
  fi

  echo "---------- sshd_config 修改前/修改后（diff 预览）----------"
  diff -u "$before_file" "$after_file" || true
  echo "--------------------------------------------------------"
  echo

  if [[ "$interactive" == "yes" ]]; then
    local cont="yes"
    prompt_yesno cont "确认应用上述修改并重启 SSH 吗" "yes"
    [[ "$cont" == "yes" ]] || die "已取消执行（未重启 SSH，未写入最终变更）。"
  fi
}

fail2ban_install() {
  if have_cmd fail2ban-server; then
    log "fail2ban 已安装"
    return 0
  fi

  if have_cmd apt-get; then
    apt-get update
    apt-get install -y fail2ban
  elif have_cmd dnf; then
    dnf install -y epel-release || true
    dnf install -y fail2ban
  elif have_cmd yum; then
    yum install -y epel-release || true
    yum install -y fail2ban
  else
    die "未识别包管理器，请手动安装 fail2ban"
  fi
}

fail2ban_write_jail_local() {
  local port="$1"
  local maxretry="$2"
  local findtime="$3"
  local bantime="$4"

  local jail_local="/etc/fail2ban/jail.local"
  if [[ ! -f "$jail_local" ]]; then
    if [[ -f /etc/fail2ban/jail.conf ]]; then
      cp -a /etc/fail2ban/jail.conf "$jail_local"
      log "已创建 $jail_local（从 jail.conf 复制）"
    else
      cat >"$jail_local" <<EOF
[DEFAULT]
bantime  = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}
EOF
      log "已创建 $jail_local（最小配置）"
    fi
  fi

  cat >>"$jail_local" <<EOF

# ---- managed by harden-ssh.sh (${TS}) ----
[sshd]
enabled  = true
port     = ${port}
filter   = sshd
logpath  = %(sshd_log)s
backend  = systemd

maxretry = ${maxretry}
findtime = ${findtime}
bantime  = ${bantime}
# -----------------------------------------
EOF

  systemctl enable --now fail2ban || true
  systemctl restart fail2ban || true
  log "fail2ban 已启用并重启"
}

main() {
  need_root
  have_cmd sshd || die "未找到 sshd（OpenSSH Server）。请先安装 openssh-server。"

  local interactive="$DEFAULT_INTERACTIVE"
  if [[ ! -t 0 ]]; then
    interactive="no"
  fi

  local new_port="$DEFAULT_PORT"
  local disable_password="$DEFAULT_DISABLE_PASSWORD"
  local enable_fail2ban="$DEFAULT_ENABLE_FAIL2BAN"
  local f2b_maxretry="$DEFAULT_FAIL2BAN_MAXRETRY"
  local f2b_findtime="$DEFAULT_FAIL2BAN_FINDTIME"
  local f2b_bantime="$DEFAULT_FAIL2BAN_BANTIME"
  local allow_users_raw="$DEFAULT_ALLOW_USERS"

  if [[ "$interactive" == "yes" ]]; then
    echo "=== SSH 加固脚本（无 UFW，A+B 优化版）==="
    echo "提示：云 VPS 请先在安全组放行你将要设置的新端口。"
    echo

    while true; do
      prompt new_port "请输入新的 SSH 端口" "$new_port"
      validate_port "$new_port" || { echo "端口不合法，请输入 1-65535 的数字。"; continue; }
      ensure_port_free_or_handle "$new_port" "$interactive" || continue
      break
    done

    prompt_yesno disable_password "是否禁用密码登录（强烈推荐）" "$disable_password"
    prompt_yesno enable_fail2ban "是否启用 Fail2Ban（推荐）" "$enable_fail2ban"

    if [[ "$enable_fail2ban" == "yes" ]]; then
      prompt f2b_maxretry "Fail2Ban：maxretry（最大尝试次数）" "$f2b_maxretry"
      prompt f2b_findtime "Fail2Ban：findtime（时间窗口，如 10m）" "$f2b_findtime"
      prompt f2b_bantime "Fail2Ban：bantime（封禁时长，如 24h）" "$f2b_bantime"
    fi

    prompt allow_users_raw "是否限制允许登录的用户（可选，逗号或空格分隔；留空表示不限制）" "$allow_users_raw"
    echo
  else
    new_port="${NEW_PORT:-$new_port}"
    disable_password="${DISABLE_PASSWORD:-$disable_password}"
    enable_fail2ban="${ENABLE_FAIL2BAN:-$enable_fail2ban}"
    f2b_maxretry="${FAIL2BAN_MAXRETRY:-$f2b_maxretry}"
    f2b_findtime="${FAIL2BAN_FINDTIME:-$f2b_findtime}"
    f2b_bantime="${FAIL2BAN_BANTIME:-$f2b_bantime}"
    allow_users_raw="${ALLOW_USERS:-$allow_users_raw}"

    validate_port "$new_port" || die "端口不合法：$new_port"
    ensure_port_free_or_handle "$new_port" "$interactive"
  fi

  local login_user; login_user="$(detect_default_user)"
  local login_home; login_home="$(get_home_of_user "$login_user")"
  log "检测到当前用户：$login_user（home: $login_home）"

  # A) 防锁死检查：禁用密码前确保至少有一套 authorized_keys
  if [[ "$disable_password" == "yes" ]]; then
    if authorized_keys_exists_for_user "$login_user"; then
      log "已检测到 $login_user 的 authorized_keys"
    elif authorized_keys_exists_for_user "root"; then
      warn "未检测到 $login_user 的 authorized_keys，但检测到 root 的 authorized_keys。"
      warn "如果你需要用 $login_user 登录，建议先为该用户配置公钥。"
      if [[ "$interactive" == "yes" ]]; then
        local cont=""
        prompt_yesno cont "仍然继续禁用密码登录吗" "no"
        if [[ "$cont" != "yes" ]]; then
          disable_password="no"
          warn "已改为：允许密码登录（避免锁死）。"
        fi
      else
        warn "非交互模式下，为避免锁死，自动将 DISABLE_PASSWORD 置为 no。"
        disable_password="no"
      fi
    else
      warn "未检测到 $login_user 或 root 的 authorized_keys。"
      if [[ "$interactive" == "yes" ]]; then
        warn "强烈建议先配置密钥登录，否则禁用密码会锁死。"
        local cont2=""
        prompt_yesno cont2 "仍然继续并禁用密码登录吗" "no"
        if [[ "$cont2" != "yes" ]]; then
          disable_password="no"
          warn "已改为：允许密码登录（避免锁死）。"
        fi
      else
        warn "非交互模式下，为避免锁死，自动将 DISABLE_PASSWORD 置为 no。"
        disable_password="no"
      fi
    fi
  fi

  local allow_users; allow_users="$(normalize_allowusers "$allow_users_raw")"

  # (1) 变更摘要（执行前）
  print_plan_summary "$login_user" "$new_port" "$disable_password" "$allow_users" \
    "$enable_fail2ban" "$f2b_maxretry" "$f2b_findtime" "$f2b_bantime"

  # 保存修改前副本用于 diff 预览
  local before_copy="${TMP_DIR}/sshd_config.before.${TS}"
  cp -a "$SSHD_CONFIG" "$before_copy"

  # 备份 sshd_config（可回滚）
  backup_file "$SSHD_CONFIG"

  # 应用 SSH 配置
  set_sshd_kv "Port" "$new_port"
  set_sshd_kv "PubkeyAuthentication" "yes"
  set_sshd_kv "AuthorizedKeysFile" ".ssh/authorized_keys"

  set_sshd_kv "PermitEmptyPasswords" "no"
  set_sshd_kv "MaxAuthTries" "3"
  set_sshd_kv "LoginGraceTime" "30"

  set_sshd_kv "X11Forwarding" "no"
  set_sshd_kv "AllowTcpForwarding" "no"
  set_sshd_kv "PermitTunnel" "no"

  set_sshd_kv "PermitRootLogin" "prohibit-password"

  if [[ "$disable_password" == "yes" ]]; then
    set_sshd_kv "PasswordAuthentication" "no"
    set_sshd_kv "KbdInteractiveAuthentication" "no"
    set_sshd_kv "ChallengeResponseAuthentication" "no"
  else
    set_sshd_kv "PasswordAuthentication" "yes"
  fi

  if [[ -n "$allow_users" ]]; then
    set_sshd_kv "AllowUsers" "$allow_users"
    log "已设置 AllowUsers: $allow_users"
  else
    remove_sshd_kv "AllowUsers"
    log "未设置 AllowUsers（不限制登录用户）"
  fi

  # 写入后副本用于 diff
  local after_copy="${TMP_DIR}/sshd_config.after.${TS}"
  cp -a "$SSHD_CONFIG" "$after_copy"

  # sshd 配置语法检查
  if sshd -t; then
    log "sshd 配置语法检查通过"
  else
    die "sshd 配置语法检查失败。请用备份回滚：${SSHD_CONFIG}.bak.${TS}"
  fi

  # (1) diff 预览 + 交互确认
  diff_preview_if_possible "$before_copy" "$after_copy" "$interactive"

  # 重启 sshd
  service_restart_sshd
  log "已重启 SSH 服务"

  # Fail2Ban
  if [[ "$enable_fail2ban" == "yes" ]]; then
    fail2ban_install
    fail2ban_write_jail_local "$new_port" "$f2b_maxretry" "$f2b_findtime" "$f2b_bantime"
  else
    log "已跳过 Fail2Ban"
  fi

  # (2) 输出可复制 SSH 命令
  echo
  echo "===== 完成 ====="
  echo "重要：请不要关闭当前 SSH 会话！先在【新终端】测试下面命令："
  echo
  echo "  ssh -p ${new_port} ${login_user}@<VPS_IP>"
  echo
  echo "（若你不是用 ${login_user} 登录，请把用户名改成实际用户）"
  echo
  echo "Fail2Ban 状态："
  echo "  sudo fail2ban-client status"
  echo "  sudo fail2ban-client status sshd"
  echo
  echo "云服务器：确认安全组已放行 TCP ${new_port}（建议仅允许你的固定 IP）。"
}

main "$@"
