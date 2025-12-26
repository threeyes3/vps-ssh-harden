# 使用教程（中文）

## 推荐流程（新 VPS）

1. 登录 VPS（密码登录）
2. 执行交互式脚本
3. 按提示设置端口、Fail2Ban
4. 粘贴或导入 SSH 公钥
5. 新终端测试新端口登录

---

## 快速运行模式

适合自动化或批量部署。

```bash
curl -fsSL https://raw.githubusercontent.com/threeyes3/vps-ssh-harden/main/harden-ssh.sh | sudo \
NEW_PORT=40022 DISABLE_PASSWORD=yes ENABLE_FAIL2BAN=yes \
GITHUB_KEYS_USER=threeyes3 bash
```

---

## 重要提示

- 请提前在云安全组放行新端口
- 永远不要关闭当前 SSH 会话
