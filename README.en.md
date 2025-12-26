## VPS SSH Hardening Script (No UFW)

[中文](README.md) | [English](README.en.md)

> ⚠️ AI-generated Notice  
> This script is generated and iteratively refined with the assistance of AI (ChatGPT).
> Review the code before production use.

A cloud-friendly SSH hardening script for Linux VPS.  
Designed to work even on fresh servers without SSH keys.

---

### Quick Start

**Interactive (recommended)**

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo bash
```

**Fast mode**

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 GITHUB_KEYS_USER=threeyes3 bash
```

---

### Documentation

- `docs/en/USAGE.md`
- `docs/en/SECURITY.md`
- `docs/en/RECOVERY.md`
