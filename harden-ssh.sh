#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# VPS SSH Hardening Script (No UFW)
#
# AI Notice:
#   This script is generated and iteratively refined with the assistance of AI (ChatGPT).
#   Please review and understand the code before using it in production.
#
# Goals:
# - Works on fresh VPS even if SSH keys are NOT deployed yet (guides key deployment)
# - Interactive (recommended) and non-interactive fast mode
# - Change SSH port with conflict detection
# - Optionally disable password login (key-only) with anti-lockout safety
# - Optional AllowUsers restriction
# - Install/configure Fail2Ban for sshd
# - Backup sshd_config, validate with sshd -t
# - Preview changes (summary + optional diff)
# - No UFW dependency (cloud security-group friendly)
# ============================================================

# --------- Defaults (can be overridden by env) ----------
DEFAULT_PORT="${DEFAULT_PORT:-}"
DEFAULT_DISABLE_PASSWORD="${DEFAULT_DISABLE_PASSWORD:-yes}"   # yes/no
DEFAULT_ENABLE_FAIL2BAN="${DEFAULT_ENABLE_FAIL2BAN:-yes}"     # yes/no
DEFAULT_FAIL2BAN_MAXRETRY="${DEFAULT_FAIL2BAN_MAXRETRY:-3}"
DEFAULT_FAIL2BAN_FINDTIME="${DEFAULT_FAIL2BAN_FINDTIME:-10m}"
DEFAULT_FAIL2BAN_BANTIME="${DEFAULT_FAIL2BAN_BANTIME:-24h}"
DEFAULT_ALLOW_USERS="${DEFAULT_ALLOW_USERS:-}"               # e.g. "ubuntu,debian,root" (comma or space separated)
DEFAULT_INTERACTIVE="${DEFAULT_INTERACTIVE:-yes}"            # yes/no
DEFAULT_KEEP_PORT="${DEFAULT_KEEP_PORT:-yes}"                # yes/no
# --------------------------------------------------------

SSHD_CONFIG="/etc/ssh/sshd_config"
TS="$(date +%Y%m%d_%H%M%S)"
TMP_DIR="/tmp/harden-ssh"
mkdir -p "$TMP_DIR"

log()  { echo -e "[+] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
err()  { echo -e "[ERR] $*" >&2; }
die()  { err "$*"; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }
is_systemd() { have_cmd systemctl; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    die "请用 root 运行：sudo bash $0"
  fi
}

# -------------------- small helpers --------------------
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

detect_default_user() {
  # best effort: detect the login user (original user before sudo), fallback to root
  echo "${SUDO_USER:-root}"
}

detect_current_sshd_port() {
  # parse first uncommented Port directive; fallback 22
  if [[ -f "$SSHD_CONFIG" ]]; then
    local port
    port="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_CONFIG" | head -n1 | awk '{print $2}')"
    if validate_port "${port:-}"; then
      echo "$port"
      return
    fi
  fi
  echo "22"
}

get_home_of_user() {
  local u="$1"
  if have_cmd getent; then
    getent passwd "$u" | awk -F: '{print $6}'
  else
    [[ "$u" == "root" ]] && echo "/root" || echo "/home/$u"
  fi
}

authorized_keys_exists_for_user() {
  local u="$1"
  local h; h="$(get_home_of_user "$u")"
  [[ -f "$h/.ssh/authorized_keys" ]] && [[ -s "$h/.ssh/authorized_keys" ]]
}

normalize_allowusers() {
  local s="$1"
  s="${s//,/ }"
  echo "$s" | awk '{$1=$1;print}'
}

# -------------------- port conflict detection --------------------
port_in_use() {
  local p="$1"
  # Return 0 if in use, 1 if free, 2 if unknown (no tools)
  if have_cmd ss; then
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
    warn "无法检测端口占用情况（系统没有 ss 或 netstat）。"
    warn "建议安装：Ubuntu/Debian -> apt install -y iproute2；CentOS/Rocky -> dnf install -y iproute"
    return 0
  fi
}

# -------------------- key provisioning (NEW) --------------------
ensure_ssh_key_for_user() {
  # Ensure target user has at least one public key in authorized_keys.
  # Supports:
  # - Interactive paste
  # - GitHub keys import (https://github.com/<user>.keys)
  # - Non-interactive via PUBKEY or GITHUB_KEYS_USER env vars
  #
  # Return:
  #   0 -> key ensured
  #   1 -> not ensured / skipped / failed

  local target_user="$1"
  local interactive="$2"

  local home_dir; home_dir="$(get_home_of_user "$target_user")"
  local ssh_dir="${home_dir}/.ssh"
  local ak="${ssh_dir}/authorized_keys"

  if authorized_keys_exists_for_user "$target_user"; then
    log "已检测到 ${target_user} 的 authorized_keys"
    return 0
  fi

  log "未检测到 ${target_user} 的 authorized_keys，准备引导部署 SSH 公钥..."

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  touch "$ak"
  chmod 600 "$ak"

  if have_cmd chown; then
    chown -R "${target_user}:${target_user}" "$ssh_dir" 2>/dev/null || true
  fi

  # Non-interactive
  if [[ "$interactive" != "yes" ]]; then
    if [[ -n "${PUBKEY:-}" ]]; then
      echo "$PUBKEY" >> "$ak"
      log "已通过环境变量 PUBKEY 写入公钥到 $ak"
      return 0
    fi

    if [[ -n "${GITHUB_KEYS_USER:-}" ]]; then
      if ! have_cmd curl; then
        err "需要 curl 才能导入 GitHub 公钥（github.com/<user>.keys）。"
        err "请安装 curl 或改用 PUBKEY 传入公钥。"
        return 1
      fi

      local keys=""
      keys="$(curl -fsSL "https://github.com/${GITHUB_KEYS_USER}.keys" 2>/dev/null || true)"
      if [[ -z "$keys" ]]; then
        err "未从 GitHub 获取到任何公钥：https://github.com/${GITHUB_KEYS_USER}.keys"
        return 1
      fi
      echo "$keys" >> "$ak"
      log "已从 GitHub(${GITHUB_KEYS_USER}) 导入公钥到 $ak"
      return 0
    fi

    return 1
  fi

  # Interactive
  echo
  echo "请选择如何为用户 ${target_user} 部署 SSH 公钥："
  echo "  1) 直接粘贴公钥（一行 ssh-ed25519/ssh-rsa ...）"
  echo "  2) 从 GitHub 用户名导入（会抓取 https://github.com/<user>.keys，请先确保公钥已添加到 GitHub）"
  echo "  3) 跳过（将保留密码登录，不会禁用密码）"
  echo

  local choice="1"
  read -r -p "请输入选项 [1]: " choice || true
  choice="${choice:-1}"

  case "$choice" in
    1)
      echo "请粘贴你的 SSH 公钥（一整行），然后回车："
      local key_line=""
      read -r key_line || true
      if [[ -z "$key_line" ]]; then
        warn "未输入公钥，部署失败。"
        return 1
      fi
      echo "$key_line" >> "$ak"
      log "已写入公钥到 $ak"
      return 0
      ;;
    2)
      if ! have_cmd curl; then
        warn "系统没有 curl，无法从 GitHub 导入。请先安装 curl 或选择粘贴公钥。"
        return 1
      fi
      local gh=""
      read -r -p "请输入 GitHub 用户名（与 github.com/<user> 保持一致）: " gh || true
      gh="${gh:-}"
      if [[ -z "$gh" ]]; then
        warn "GitHub 用户名为空。"
        return 1
      fi
      local keys=""
      keys="$(curl -fsSL "https://github.com/${gh}.keys" 2>/dev/null || true)"
      if [[ -z "$keys" ]]; then
        warn "未从 GitHub 获取到任何公钥：https://github.com/${gh}.keys"
        return 1
      fi
      echo "$keys" >> "$ak"
      log "已从 GitHub(${gh}) 导入公钥到 $ak"
      return 0
      ;;
    3)
      warn "已选择跳过公钥部署。"
      return 1
      ;;
    *)
      warn "无效选项。"
      return 1
      ;;
  esac
}

# -------------------- sshd config ops --------------------
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
    sed -ri "s|^[[:space:]]*(${key}[[:space:]].*)|# \\1|I" "$SSHD_CONFIG"
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

# -------------------- preview helpers --------------------
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
  echo "目标用户（用于生成 SSH 命令）: ${login_user}"
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
    [[ "$cont" == "yes" ]] || die "已取消执行。"
  fi
}

# -------------------- fail2ban --------------------
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

  # predictable override block
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

# -------------------- main --------------------
main() {
  need_root
  have_cmd sshd || die "未找到 sshd（OpenSSH Server）。请先安装 openssh-server。"

  local interactive="$DEFAULT_INTERACTIVE"
  if [[ -t 0 ]]; then
    interactive="yes"
  elif [[ "${FORCE_INTERACTIVE:-no}" == "yes" ]]; then
    interactive="yes"
  else
    interactive="no"
  fi

  # config from defaults
  local current_port; current_port="$(detect_current_sshd_port)"
  local new_port="$DEFAULT_PORT"
  if [[ -z "$new_port" ]]; then
    new_port="$current_port"
  fi
  local disable_password="$DEFAULT_DISABLE_PASSWORD"
  local enable_fail2ban="$DEFAULT_ENABLE_FAIL2BAN"
  local f2b_maxretry="$DEFAULT_FAIL2BAN_MAXRETRY"
  local f2b_findtime="$DEFAULT_FAIL2BAN_FINDTIME"
  local f2b_bantime="$DEFAULT_FAIL2BAN_BANTIME"
  local allow_users_raw="$DEFAULT_ALLOW_USERS"

  # collect inputs
  if [[ "$interactive" == "no" && "${AUTO_PROCEED:-no}" != "yes" ]]; then
    die "检测到非交互执行（例如 curl 管道）。请在交互终端运行，或确认配置无误后设置 AUTO_PROCEED=yes（可配合 FORCE_INTERACTIVE=yes）。"
  fi

  if [[ "$interactive" == "yes" ]]; then
    echo "=== SSH 加固脚本（无 UFW）==="
    echo "提示：云 VPS 请先在安全组放行你将要设置的新端口。"
    echo

    local keep_port_answer="$DEFAULT_KEEP_PORT"
    prompt_yesno keep_port_answer "是否保留当前 SSH 端口 ${current_port}" "$keep_port_answer"
    if [[ "$keep_port_answer" == "no" ]]; then
      while true; do
        prompt new_port "请输入新的 SSH 端口" "$new_port"
        validate_port "$new_port" || { echo "端口不合法，请输入 1-65535 的数字。"; continue; }
        ensure_port_free_or_handle "$new_port" "$interactive" || continue
        break
      done
    else
      new_port="$current_port"
    fi

    prompt_yesno disable_password "是否禁用密码登录（强烈推荐，需确保有公钥）" "$disable_password"
    prompt_yesno enable_fail2ban "是否启用 Fail2Ban（推荐）" "$enable_fail2ban"

    if [[ "$enable_fail2ban" == "yes" ]]; then
      prompt f2b_maxretry "Fail2Ban：maxretry（最大尝试次数）" "$f2b_maxretry"
      prompt f2b_findtime "Fail2Ban：findtime（时间窗口，如 10m）" "$f2b_findtime"
      prompt f2b_bantime "Fail2Ban：bantime（封禁时长，如 24h）" "$f2b_bantime"
    fi

    prompt allow_users_raw "AllowUsers（可选，逗号或空格分隔；留空表示不限制）" "$allow_users_raw"
    echo
  else
    # non-interactive: env overrides
    new_port="${NEW_PORT:-$new_port}"
    disable_password="${DISABLE_PASSWORD:-$disable_password}"
    enable_fail2ban="${ENABLE_FAIL2BAN:-$enable_fail2ban}"
    f2b_maxretry="${FAIL2BAN_MAXRETRY:-$f2b_maxretry}"
    f2b_findtime="${FAIL2BAN_FINDTIME:-$f2b_findtime}"
    f2b_bantime="${FAIL2BAN_BANTIME:-$f2b_bantime}"
    allow_users_raw="${ALLOW_USERS:-$allow_users_raw}"

    local keep_port="${KEEP_PORT:-$DEFAULT_KEEP_PORT}"
    if [[ "$keep_port" == "yes" && -z "${NEW_PORT:-}" ]]; then
      new_port="$current_port"
    fi

    validate_port "$new_port" || die "端口不合法：$new_port"
    ensure_port_free_or_handle "$new_port" "$interactive"
  fi

  local login_user; login_user="$(detect_default_user)"
  local login_home; login_home="$(get_home_of_user "$login_user")"
  log "检测到当前用户：$login_user（home: $login_home）"

  local allow_users; allow_users="$(normalize_allowusers "$allow_users_raw")"

  # NEW: ensure key before disabling password (works on fresh VPS)
  if [[ "$disable_password" == "yes" ]]; then
    if ensure_ssh_key_for_user "$login_user" "$interactive"; then
      log "已为 $login_user 准备好 SSH 公钥，可安全禁用密码登录。"
    else
      warn "未能为 $login_user 部署 SSH 公钥。为避免锁死，将自动保留密码登录。"
      disable_password="no"
    fi
  fi

  # (1) summary before applying
  print_plan_summary "$login_user" "$new_port" "$disable_password" "$allow_users" \
    "$enable_fail2ban" "$f2b_maxretry" "$f2b_findtime" "$f2b_bantime"

  if [[ "$interactive" == "yes" ]]; then
    local proceed="yes"
    prompt_yesno proceed "确认应用上述修改并继续吗" "yes"
    [[ "$proceed" == "yes" ]] || die "已取消执行。"
  else
    if [[ "${AUTO_PROCEED:-no}" != "yes" ]]; then
      die "检测到非交互执行。为安全起见，需设置 AUTO_PROCEED=yes 才会继续。"
    fi
  fi

  # snapshot for diff preview
  local before_copy="${TMP_DIR}/sshd_config.before.${TS}"
  cp -a "$SSHD_CONFIG" "$before_copy"

  # backup for rollback
  backup_file "$SSHD_CONFIG"
  local backup_path="${SSHD_CONFIG}.bak.${TS}"

  # apply sshd config
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

  # snapshot after applying for diff preview
  local after_copy="${TMP_DIR}/sshd_config.after.${TS}"
  cp -a "$SSHD_CONFIG" "$after_copy"

  # validate sshd config
  if sshd -t; then
    log "sshd 配置语法检查通过"
  else
    die "sshd 配置语法检查失败。请用备份回滚：${SSHD_CONFIG}.bak.${TS}"
  fi

  # (2) diff preview + confirmation
  diff_preview_if_possible "$before_copy" "$after_copy" "$interactive"

  # restart sshd
  service_restart_sshd
  log "已重启 SSH 服务"

  # fail2ban
  if [[ "$enable_fail2ban" == "yes" ]]; then
    fail2ban_install
    fail2ban_write_jail_local "$new_port" "$f2b_maxretry" "$f2b_findtime" "$f2b_bantime"
    if systemctl is-active --quiet fail2ban; then
      log "fail2ban 服务运行中：$(systemctl status fail2ban --no-pager | head -n 3 | tr '\\n' ' ')"
    else
      warn "fail2ban 未成功运行，请执行：systemctl status fail2ban 查看日志。"
    fi
  else
    log "已跳过 Fail2Ban"
  fi

  # (3) print final next steps
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

  if [[ "$interactive" == "yes" ]]; then
    echo
    local rollback="no"
    prompt_yesno rollback "是否立即撤回本次修改并恢复到备份（${backup_path}）" "no"
    if [[ "$rollback" == "yes" ]]; then
      cp -a "$backup_path" "$SSHD_CONFIG"
      service_restart_sshd
      if [[ "$enable_fail2ban" == "yes" ]]; then
        systemctl stop fail2ban || true
      fi
      log "已恢复 sshd 配置备份并重启 SSH。若启用了 Fail2Ban 已尝试停止。"
      exit 0
    fi
  fi
}

main "$@"
DEFAULT_KEEP_PORT="${DEFAULT_KEEP_PORT:-yes}"                # yes/no
