## VPS SSH Hardening Script (No UFW)

[中文](README.md) | [English](README.en.md)

> ⚠️ AI-generated Notice  
> This script is generated and iteratively refined with the assistance of AI (ChatGPT).
> Review and understand the code before production use.

---

### What / When / How

A cloud-friendly SSH hardening script for Linux VPS, designed to safely apply common SSH security practices
(port change, key-only login, Fail2Ban) without relying on UFW.

Use it when provisioning new VPS instances or automating SSH hardening across servers,
especially when you want to avoid accidental lockouts.

Interactive mode is recommended for first-time use; fast mode is available once you understand the behavior.

---

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo bash
```

### SSH key quick note

- The script runs on the VPS only; generate your key **locally** first.
- We recommend ed25519 (e.g., `ssh-keygen -t ed25519 -C "label"`). For detailed steps and the local key helper, see User Guide §1.3:  
  👉 [Key generation & helper](docs/en/GUIDE.md#13-ssh-key-generation-on-your-pc)

---
### 📘 User Guide (Recommended)

👉 **[Read the full user guide](docs/en/GUIDE.md)**

> This guide covers:  
> - Recommended workflow for new VPS instances  
> - Correct usage of fast (non-interactive) mode  
> - Security design decisions and trade-offs  
> - Recovery and rollback in case of SSH lockout  

**If you only read one document, read this one.**
