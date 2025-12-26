## VPS SSH 加固脚本（无 UFW）

[中文](README.md) | [English](README.en.md)

> ⚠️ **AI 生成声明（重要）**  
> 本项目脚本由 **AI（ChatGPT）生成并在人工指导下多轮完善**。  
> 在生产环境使用前，请务必自行阅读、理解并测试代码。  
> 使用风险需自行承担。

---

### What / When / How

这是一个面向 **Linux VPS** 的 **SSH 一键加固脚本**，用于在 **云服务器环境** 下，
**安全地** 完成诸如修改 SSH 端口、禁用密码登录、启用 Fail2Ban 等基础加固操作。

当你刚创建了一台 **仅支持密码登录的新 VPS**，或你希望为多台服务器
**统一、自动化** 地执行 SSH 加固，同时又不想因为误配置而把自己锁在服务器之外时，
这个脚本正是为此场景设计的。

推荐使用方式是 **交互式运行**（脚本会引导你部署 SSH 密钥并做防锁死检查）；
在你完全理解脚本行为后，也可以使用 **快速运行模式** 进行批量或自动化部署。

---

### Quick Start

**交互式（推荐）**

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo bash
```

**快速运行（非交互）**

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 DISABLE_PASSWORD=yes \
GITHUB_KEYS_USER=threeyes3 \
bash
```

### 本地密钥助手（生成 SSH 公钥）

- 作用：在 **本地电脑** 一键生成 ed25519 密钥对，并显示/保存公钥，供脚本粘贴使用。
- macOS/Linux：先下载仓库或脚本，然后运行  
  ```bash
  bash tools/local-key-helper.sh
  ```  
  若仅下载脚本：  
  ```bash
  curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/tools/local-key-helper.sh -o local-key-helper.sh
  bash local-key-helper.sh
  ```
- Windows：下载仓库或脚本后，右键使用 PowerShell 运行 `tools/local-key-helper.ps1`（如需放行脚本，可在 PowerShell 中先执行：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`）。

---

### 📘 使用指南（必读）

👉 **[阅读完整使用指南](docs/zh/GUIDE.md)**

> 本指南将带你完整了解：  
> - 新 VPS 的推荐使用流程  
> - 快速运行模式的正确用法  
> - 脚本的安全设计与取舍  
> - SSH 锁死后的回滚与救援  

**如果你只阅读一份文档，请阅读这里。**
