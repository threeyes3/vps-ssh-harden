# SSH 加固使用指南（中文）

本指南是本项目的 **唯一完整文档**，用于说明如何在不同场景下安全地使用脚本。

---

## 1. 阅读前须知（一定要读）

### 1.1 关于锁死风险

任何 SSH 配置变更都存在把自己锁在服务器之外的风险。
本脚本已经尽量通过以下方式降低风险：

- 交互式引导
- 禁用密码前的公钥检查与引导部署
- sshd 配置语法校验（`sshd -t`）

但 **最终责任仍在使用者本人**。

### 1.2 云安全组优先原则

本脚本 **不配置 UFW**。
在云 VPS 场景下，请始终以 **云厂商安全组** 作为第一道防线。

在修改 SSH 端口前，请务必：

- 先在安全组中放行新端口
- 再执行脚本

### 1.3 关于 SSH 密钥生成（在你的电脑上完成）

核心原则：**密钥只在本地电脑生成和保存，VPS 上不生成、不存私钥。**

#### 自己生成（推荐）
1. macOS/Linux 打开终端，或 Windows 打开 PowerShell。  
2. 运行：`ssh-keygen -t ed25519 -C "你的备注或邮箱"`，回车接受默认路径，按需设置口令。  
3. 公钥位置：`~/.ssh/id_ed25519.pub`（Windows: `C:\\Users\\你\\.ssh\\id_ed25519.pub`），复制整行备用。

#### 如需可视/免命令方式
- 你可以使用任意可信的本地工具生成公钥，也可以使用在线生成器（请自查可信度，我们不做推荐；注意不要泄露私钥）。

#### 本仓库提供的双语“本地密钥助手”
- 位置：`tools/local-key-helper.sh`（macOS/Linux），`tools/local-key-helper.ps1`（Windows）。
- 用法：双击或在终端运行后，选择语言（中文/English），按提示一键生成 ed25519 密钥对并显示公钥，桌面会保存 `ssh_public_key.txt` 便于复制。

完成后，在运行加固脚本时粘贴你的公钥（或先把公钥添加到 GitHub，再用 GitHub 导入方式）。

---

## 2. 推荐使用流程

### 场景 A：全新 VPS（仅密码登录）

这是最推荐、也是最常见的使用场景。

1. 使用密码登录 VPS
2. 执行脚本（交互式）
3. 根据提示：
   - 设置新的 SSH 端口
   - 选择是否启用 Fail2Ban
   - 粘贴或从 GitHub 导入 SSH 公钥
4. 脚本完成后，**不要关闭当前会话**
5. 在新终端使用新端口测试 SSH 登录

### 场景 B：已部署 SSH 密钥的 VPS

流程与上面类似，但脚本会直接检测到已存在的公钥并跳过引导步骤。

---

## 3. 快速运行模式（非交互）

### 3.1 什么时候使用

仅在以下情况推荐使用快速运行模式：

- 你已经完整阅读并理解本脚本行为
- 你确认目标 VPS 已允许新 SSH 端口
- 你明确传入了 SSH 公钥或 GitHub 用户名

### 3.2 示例

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 DISABLE_PASSWORD=yes ENABLE_FAIL2BAN=yes \
GITHUB_KEYS_USER=threeyes3 \
bash
```

可选参数（环境变量）速览：
- `NEW_PORT`：新的 SSH 端口（默认 2222）
- `DISABLE_PASSWORD`：是否禁用密码登录（yes/no，默认 yes，若无密钥会自动保留密码）
- `ENABLE_FAIL2BAN`：是否启用 Fail2Ban（yes/no，默认 yes）
- `FAIL2BAN_MAXRETRY`：最大尝试次数（默认 3）
- `FAIL2BAN_FINDTIME`：时间窗口（默认 10m）
- `FAIL2BAN_BANTIME`：封禁时长（默认 24h）
- `ALLOW_USERS`：AllowUsers 列表（逗号或空格分隔；留空不限制）
- `KEEP_PORT`：是否保留当前 SSH 端口（yes/no，默认 yes，如设为 no 请设置 NEW_PORT）
- `PUBKEY`：直接传入公钥
- `GITHUB_KEYS_USER`：从 GitHub 导入公钥
- `AUTO_PROCEED`：非交互模式下是否自动执行（yes/no，默认 no；设置 yes 才会继续）
- `FORCE_INTERACTIVE`：在管道运行时强制交互（yes/no，默认 no；例如 curl | bash 时可设为 yes）

说明：若未提供 `PUBKEY` 或 `GITHUB_KEYS_USER`，脚本会为避免锁死 **自动保留密码登录**。

---

## 4. 脚本做了什么（透明说明）

### 4.1 SSH 相关

- 修改 SSH 监听端口
- 可选禁用密码登录
- 设置合理的 SSH 安全参数
- 自动备份并校验配置

### 4.2 Fail2Ban

- 仅启用 `sshd` jail
- 使用保守默认参数
- 通过系统防火墙机制封禁 IP

### 4.3 明确不做的事

- 不配置 UFW
- 不修改云安全组
- 不做系统级“极限加固”

---

## 5. 执行后检查清单

- 新端口 SSH 是否可登录
- 原会话是否仍然保持
- Fail2Ban 状态是否正常

---

## 6. 故障排查与回滚

### 6.1 SSH 无法登录

使用云厂商控制台登录服务器，执行：

```bash
ls /etc/ssh/sshd_config.bak.*
cp /etc/ssh/sshd_config.bak.<时间戳> /etc/ssh/sshd_config
systemctl restart sshd
```

### 6.2 Fail2Ban 误封

```bash
fail2ban-client set sshd unbanip <IP>
```

---

---
