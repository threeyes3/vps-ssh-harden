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

---

### Documentation

- `docs/en/GUIDE.md`
