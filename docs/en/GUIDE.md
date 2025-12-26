# SSH Hardening Guide (English)

This document is the single, complete guide for using this project.

---

## Before You Start

- Always keep your current SSH session open
- Open the new SSH port in your cloud security group first
- Interactive mode is strongly recommended for first-time use
- Keys must be generated **locally** (on your PC), not on the VPS. The hardening script runs only on the VPS.

---

## Recommended Usage

Run the script interactively:

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo bash
```

The script will guide you through key deployment and safety checks.

---

## 1.3 SSH key generation (on your PC)

Principle: generate and keep keys locally; do not create or store private keys on the VPS.

**DIY (recommended)**
1) macOS/Linux: open Terminal; Windows: open PowerShell.  
2) Run `ssh-keygen -t ed25519 -C "your note or email"`; press Enter for the default path; set a passphrase if desired.  
3) Public key path: `~/.ssh/id_ed25519.pub` (Windows: `C:\\Users\\you\\.ssh\\id_ed25519.pub`). Copy the full line.

**If you prefer GUI/no commands**
- Use any trusted local tool you like. Online generators exist, but check trustworthiness yourself; never disclose your private key.

**Bundled bilingual helper (optional)**
- Provided in the repo: `tools/local-key-helper.sh` (macOS/Linux), `tools/local-key-helper.ps1` (Windows).
- Double-click or run in a terminal, choose language (中文/English), follow prompts to create an ed25519 keypair and view the public key. It also saves `ssh_public_key.txt` on your Desktop for easy copy/paste.

---

## Fast Mode

Fast mode is intended for automation and advanced users only.

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 GITHUB_KEYS_USER=threeyes3 bash
```

Optional env vars:
- `NEW_PORT` (default 2222)
- `DISABLE_PASSWORD` (yes/no, default yes; if no key provided it keeps password auth to avoid lockout)
- `ENABLE_FAIL2BAN` (yes/no, default yes)
- `FAIL2BAN_MAXRETRY` (default 3)
- `FAIL2BAN_FINDTIME` (default 10m)
- `FAIL2BAN_BANTIME` (default 24h)
- `ALLOW_USERS` (comma/space list; empty means no restriction)
- `KEEP_PORT` (yes/no, default yes; set to no and provide NEW_PORT to change)
- `PUBKEY` (inline public key)
- `GITHUB_KEYS_USER` (fetch keys from GitHub)
- `AUTO_PROCEED` (yes/no, default no; set yes to allow non-interactive run to continue)
- `FORCE_INTERACTIVE` (yes/no, default no; set yes to stay interactive when running via pipe like curl | bash)

Note: if neither `PUBKEY` nor `GITHUB_KEYS_USER` is set, the script keeps password auth to prevent lockout.

---

## Recovery

Restore the SSH configuration backup if needed and restart sshd.
