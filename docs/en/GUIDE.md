# SSH Hardening Guide (English)

This document is the single, complete guide for using this project.

---

## Before You Start

- Always keep your current SSH session open
- Open the new SSH port in your cloud security group first
- Interactive mode is strongly recommended for first-time use
- Keys must be generated **locally** (on your PC), not on the VPS. The hardening script runs only on the VPS; a local “key helper” is a separate, one-click tool on Windows/macOS with a language selector (中文/English) that just creates a new keypair and shows the public key.

---

## Recommended Usage

Run the script interactively:

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo bash
```

The script will guide you through key deployment and safety checks.

---

## Fast Mode

Fast mode is intended for automation and advanced users only.

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 GITHUB_KEYS_USER=threeyes3 bash
```

---

## Local Key Helper (one-click, bilingual)

- Use the bundled helpers (double-click, no commands needed):  
  - macOS/Linux: `tools/local-key-helper.sh`  
  - Windows: `tools/local-key-helper.ps1`
- When opened, first choose language (中文/English), then the helper directly runs `ssh-keygen -t ed25519 -C "your_label_here"` to create a new keypair. The `-C` comment is just a label (often an email) to identify the key; it does not affect security. Users can type any label they like.
- After generation, the helper shows the public key and saves it to an easy place (e.g., Desktop `ssh_public_key.txt`). Copy the whole line and paste it into the VPS script prompt (or upload to GitHub and import).

---

## Recovery

Restore the SSH configuration backup if needed and restart sshd.
