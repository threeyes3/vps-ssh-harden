# A simple local SSH key helper for Windows (PowerShell).
# - Runs locally (not on VPS)
# - Bilingual prompts (中文 / English)
# - One-click style: pick language, choose label & file name, generate key, show/save public key

function Select-Language {
    Write-Host "请选择语言 / Choose language:"
    Write-Host "  1) 中文"
    Write-Host "  2) English"
    $choice = Read-Host "[1]"
    switch ($choice) {
        "2" { return "en" }
        default { return "zh" }
    }
}

function Msg($lang, $key) {
    if ($lang -eq "zh") {
        switch ($key) {
            "need_ssh_keygen" { "未找到 ssh-keygen，请先安装 OpenSSH 客户端（含 ssh-keygen）。" }
            "intro" { "本工具只在本地运行，用于生成新的 SSH 密钥对，不会修改 VPS。" }
            "label_prompt" { "请输入用于标记密钥的文字（可填邮箱或备注） [my-key]:" }
            "filename_prompt" { "保存私钥的文件名（默认: id_ed25519_vps，不会覆盖已存在文件）：" }
            "exists_prompt" { "文件已存在，想要改用其他文件名吗？(y/N): " }
            "gen_start" { "开始生成 ed25519 密钥对..." }
            "gen_done" { "密钥生成完成。" }
            "desktop_saved" { "公钥已保存到：" }
            "copy_tip" { "请复制下面整行公钥，稍后在 VPS 脚本提示处粘贴：" }
            "final_tip" { "完成后即可关闭此窗口，然后在 VPS 上运行加固脚本并粘贴公钥。" }
        }
    }
    else {
        switch ($key) {
            "need_ssh_keygen" { "ssh-keygen not found. Install OpenSSH client (includes ssh-keygen) first." }
            "intro" { "This helper runs locally only. It generates a new SSH keypair; it does not touch your VPS." }
            "label_prompt" { "Enter a label for the key (email or note) [my-key]:" }
            "filename_prompt" { "Key file name to save (default: id_ed25519_vps; existing files are not overwritten):" }
            "exists_prompt" { "File already exists. Do you want to choose another name? (y/N): " }
            "gen_start" { "Generating ed25519 keypair..." }
            "gen_done" { "Key generation completed." }
            "desktop_saved" { "Public key saved to:" }
            "copy_tip" { "Copy the full public key line below and paste into the VPS script when prompted:" }
            "final_tip" { "You can close this window and run the VPS hardening script, then paste the public key." }
        }
    }
}

$lang = Select-Language
Write-Host ""
Write-Host (Msg $lang "intro")
Write-Host ""

if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    Write-Host (Msg $lang "need_ssh_keygen")
    exit 1
}

$sshDir = Join-Path $HOME ".ssh"
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }

$label = Read-Host (Msg $lang "label_prompt")
if ([string]::IsNullOrWhiteSpace($label)) { $label = "my-key" }

$keyBase = Read-Host (Msg $lang "filename_prompt")
if ([string]::IsNullOrWhiteSpace($keyBase)) { $keyBase = "id_ed25519_vps" }

$keyPath = Join-Path $sshDir $keyBase
if (Test-Path $keyPath) {
    $suffix = Get-Date -Format "yyyyMMddHHmmss"
    $keyPath = "${keyPath}_${suffix}"
}

Write-Host ""
Write-Host (Msg $lang "gen_start")
Write-Host ""

ssh-keygen -t ed25519 -C "$label" -f "$keyPath"

Write-Host ""
Write-Host (Msg $lang "gen_done")

$pubFile = "${keyPath}.pub"
$desktop = Join-Path $HOME "Desktop"
$savePath = Join-Path $desktop "ssh_public_key.txt"
if (-not (Test-Path $desktop)) {
    $savePath = Join-Path $HOME "ssh_public_key.txt"
}

Copy-Item -Path $pubFile -Destination $savePath -Force

Write-Host (Msg $lang "desktop_saved") $savePath
Write-Host ""
Write-Host (Msg $lang "copy_tip")
Write-Host ""
Get-Content $pubFile
Write-Host ""
Write-Host (Msg $lang "final_tip")
