## VPS SSH 加固脚本（无 UFW）

[中文](README.md) | [English](README.en.md)

> ⚠️ **AI 生成声明（重要）**  
> 本项目中的脚本由 **AI（ChatGPT）生成并在人工指导下多轮完善**。  
> 在生产环境使用前，请务必自行阅读、理解并测试脚本内容。  
> 使用本脚本造成的任何风险与后果需自行承担。

---

### 这是什么？

这是一个面向 **Linux VPS** 的 **SSH 一键加固脚本**。  
在不依赖 UFW 的前提下，帮助你完成最常见、也是最容易出问题的 SSH 加固操作。

脚本针对 **云服务器环境** 设计，并支持 **全新 VPS（仅密码登录）** 的安全引导。

---

### 适用场景

- 你管理多台 VPS，希望快速、统一地完成 SSH 基础加固
- 你使用云厂商 **安全组** 管理入站规则，而非本机防火墙
- 你希望既有交互式引导（避免误操作），也支持一行命令自动化部署

---

### 核心特性

- ✅ 支持全新 VPS：无 SSH 密钥也可运行（粘贴 / GitHub 导入）
- ✅ 交互式（推荐）与快速运行（非交互）两种模式
- ✅ SSH 端口修改（含端口占用检测）
- ✅ 禁用密码登录的防锁死保护
- ✅ Fail2Ban 基础防护
- ✅ 自动备份并校验 `sshd_config`
- ✅ 不依赖 UFW，更适配云安全组

---

### 快速开始

#### 方式一：交互式（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo bash
```

#### 方式二：快速运行（非交互）

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 DISABLE_PASSWORD=yes ENABLE_FAIL2BAN=yes \
GITHUB_KEYS_USER=threeyes3 \
bash
```

---

### 文档（中文）

- 📘 使用教程  
  `docs/zh/USAGE.md`
- 🔐 安全设计说明  
  `docs/zh/SECURITY.md`
- 🛟 救援与回滚  
  `docs/zh/RECOVERY.md`

---

### 安全 TL;DR

- 不要关闭当前 SSH 会话；先在新终端测试新端口
- 云 VPS 请先在安全组放行新端口
- 禁用密码登录前务必确认密钥可用

---

MIT License · Use at your own risk.
