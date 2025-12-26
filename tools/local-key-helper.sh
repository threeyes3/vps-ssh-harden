#!/usr/bin/env bash
set -euo pipefail

# A simple local SSH key helper for macOS/Linux.
# - Runs locally (not on VPS)
# - Bilingual prompts (中文 / English)
# - One-click style: pick language, choose label & file name, generate key, show/save public key

detect_lang() {
  if [[ "${LANG:-}" == zh* ]]; then
    echo "zh"
  else
    echo "en"
  fi
}

LANG_CHOICE=""

prompt_lang() {
  echo "请选择语言 / Choose language:"
  echo "  1) 中文"
  echo "  2) English"
  read -r -p "[1]: " choice || true
  case "${choice:-1}" in
    1) LANG_CHOICE="zh" ;;
    2) LANG_CHOICE="en" ;;
    *) LANG_CHOICE="$(detect_lang)" ;;
  esac
}

msg() {
  local key="$1"
  case "$LANG_CHOICE" in
    zh)
      case "$key" in
        need_ssh_keygen) echo "未找到 ssh-keygen，请先安装 OpenSSH 客户端（含 ssh-keygen）。" ;;
        intro) echo "本工具只在本地运行，用于生成新的 SSH 密钥对，不会修改 VPS。" ;;
        label_prompt) echo "请输入用于标记密钥的文字（可填邮箱或备注） [my-key]:" ;;
        filename_prompt) echo "保存私钥的文件名（默认: id_ed25519_vps，不会覆盖已存在文件）：" ;;
        exists_prompt) echo "文件已存在，想要改用其他文件名吗？(y/N): " ;;
        gen_start) echo "开始生成 ed25519 密钥对..." ;;
        gen_done) echo "密钥生成完成。" ;;
        desktop_saved) echo "公钥已保存到：" ;;
        copy_tip) echo "请复制下面整行公钥，稍后在 VPS 脚本提示处粘贴：" ;;
        final_tip) echo "完成后即可关闭此窗口，然后在 VPS 上运行加固脚本并粘贴公钥。" ;;
      esac
      ;;
    *)
      case "$key" in
        need_ssh_keygen) echo "ssh-keygen not found. Install OpenSSH client (includes ssh-keygen) first." ;;
        intro) echo "This helper runs locally only. It generates a new SSH keypair; it does not touch your VPS." ;;
        label_prompt) echo "Enter a label for the key (email or note) [my-key]:" ;;
        filename_prompt) echo "Key file name to save (default: id_ed25519_vps; existing files are not overwritten):" ;;
        exists_prompt) echo "File already exists. Do you want to choose another name? (y/N): " ;;
        gen_start) echo "Generating ed25519 keypair..." ;;
        gen_done) echo "Key generation completed." ;;
        desktop_saved) echo "Public key saved to:" ;;
        copy_tip) echo "Copy the full public key line below and paste into the VPS script when prompted:" ;;
        final_tip) echo "You can close this window and run the VPS hardening script, then paste the public key." ;;
      esac
      ;;
  esac
}

ensure_ssh_keygen() {
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "$(msg need_ssh_keygen)"
    exit 1
  fi
}

main() {
  prompt_lang
  [[ -n "$LANG_CHOICE" ]] || LANG_CHOICE="$(detect_lang)"

  echo
  echo "$(msg intro)"
  echo

  ensure_ssh_keygen

  local ssh_dir="$HOME/.ssh"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir" 2>/dev/null || true

  local label=""
  read -r -p "$(msg label_prompt) " label || true
  label="${label:-my-key}"

  local key_base=""
  read -r -p "$(msg filename_prompt) " key_base || true
  key_base="${key_base:-id_ed25519_vps}"

  local key_path="$ssh_dir/$key_base"
  if [[ -f "$key_path" ]]; then
    # avoid overwriting existing keys silently; place new key with timestamp suffix
    key_path="${key_path}_$(date +%Y%m%d%H%M%S)"
  fi

  echo
  echo "$(msg gen_start)"
  echo

  ssh-keygen -t ed25519 -C "$label" -f "$key_path"

  echo
  echo "$(msg gen_done)"

  local pub_file="${key_path}.pub"
  local desktop="${HOME}/Desktop"
  local save_path="$desktop/ssh_public_key.txt"
  if [[ ! -d "$desktop" ]]; then
    save_path="${HOME}/ssh_public_key.txt"
  fi

  mkdir -p "$(dirname "$save_path")"
  cp "$pub_file" "$save_path"

  echo "$(msg desktop_saved) $save_path"
  echo
  echo "$(msg copy_tip)"
  echo
  cat "$pub_file"
  echo
  echo "$(msg final_tip)"
}

main "$@"
