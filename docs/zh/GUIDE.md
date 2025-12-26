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

脚本不会在服务器上生成密钥，私钥必须保存在 **你的本地电脑**。加固脚本只运行在 VPS 上；密钥助手则是你在本地电脑单独打开的小工具，专门用来“生成一对新密钥并展示公钥”，不需要先检查你本地是否已有密钥。本指南为中英双语，建议密钥助手在启动时提供“选择语言（中文/English）”的提示，后续步骤用所选语言呈现。为零基础用户，建议在 Windows 或 macOS 上按下面的“本地密钥助手”思路操作：

**工具设计（双击即用，专注一键生成）**
- 形态：一个可执行文件或桌面快捷方式，双击就运行；启动后先让用户选择语言（中文/English），全程提示无需敲命令。
- 目标：直接生成新的 ed25519 密钥对（不做“是否已有”的复杂检查），内部调用 `ssh-keygen -t ed25519 -C "your_label_here"`，提示“按回车接受默认路径”“设置密钥口令（建议）”。这里的 `-C` 注释字段只是给密钥打标签（常见是邮箱），不影响功能，用户可以输入邮箱或任何用于识别的文字。
- 完成后自动：
  - 确认私钥权限（macOS/Linux: `chmod 600`；Windows 不需要处理权限）。
  - 把公钥内容显示在窗口/终端，并额外保存到易找的文件（macOS: `~/Desktop/ssh_public_key.txt`，Windows: `C:\\Users\\<你>\\Desktop\\ssh_public_key.txt`），方便复制。
  - 可选：把公钥整理到一个清单文件（macOS: `~/.ssh/vps_keys/public_keys.txt`，Windows: `C:\\Users\\<你>\\.ssh\\vps_keys\\public_keys.txt`），便于备份。

**零基础快速步骤（无需懂命令）**
1) 在你的电脑上 **双击打开“本地密钥助手”**（无需输入命令），本仓库已提供：  
   - macOS/Linux：`tools/local-key-helper.sh`  
   - Windows：`tools/local-key-helper.ps1`  
2) 进入工具后，先选择语言（中文/English），再按提示一路回车即可生成新的密钥对，并看到“公钥”内容；桌面会生成 `ssh_public_key.txt` 方便复制。  
3) 复制整行公钥。  
4) 登录 VPS 运行本项目脚本时，按提示粘贴这行公钥（或先把公钥添加到你的 GitHub 账号，再用 GitHub 导入方式）。

这样即使从零基础开始，也能在本地安全生成并保存密钥，再安全地在 VPS 上应用加固脚本。

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

如果你不提供 `PUBKEY` 或 `GITHUB_KEYS_USER`，
脚本将为了安全 **自动保留密码登录**，以避免锁死。

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

## 7. 参数参考（速查）

- `NEW_PORT`：新的 SSH 端口
- `DISABLE_PASSWORD`：是否禁用密码登录
- `ENABLE_FAIL2BAN`：是否启用 Fail2Ban
- `PUBKEY`：直接传入 SSH 公钥
- `GITHUB_KEYS_USER`：从 GitHub 导入公钥
