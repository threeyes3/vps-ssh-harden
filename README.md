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
curl -fsSLO https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh
sudo bash harden-ssh.sh
```

**快速运行（非交互）**

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 DISABLE_PASSWORD=yes \
GITHUB_KEYS_USER=threeyes3 \
bash
```

### SSH 密钥简要说明

- 脚本只在 VPS 上运行，不会帮你在服务器生成密钥；请在 **本地电脑** 先准备好公钥。
- 推荐使用 ed25519 密钥（如 `ssh-keygen -t ed25519 -C "label"`）。详细步骤与本地密钥助手用法，见使用手册 1.3 节：  
  👉 [密钥生成与助手说明](docs/zh/GUIDE.md#13-%E5%85%B3%E4%BA%8E-ssh-%E5%AF%86%E9%92%A5%E7%94%9F%E6%88%90%E5%9C%A8%E4%BD%A0%E7%9A%84%E7%94%B5%E8%84%91%E4%B8%8A%E5%AE%8C%E6%88%90)

---

### 📘 使用指南（必读）

👉 **[阅读完整使用指南](docs/zh/GUIDE.md)**

> 本指南将带你完整了解：  
> - 新 VPS 的推荐使用流程  
> - 快速运行模式的正确用法  
> - 脚本的安全设计与取舍  
> - SSH 锁死后的回滚与救援  

**如果你只阅读一份文档，请阅读这里。**
