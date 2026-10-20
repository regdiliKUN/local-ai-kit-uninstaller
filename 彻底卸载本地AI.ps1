<#
  ============================================================================
  彻底卸载 local-ai-kit（本地 AI 部署包） — 干净清理工具
  ----------------------------------------------------------------------------
  适用场景：
    1) 把 GitHub 上的 regdiliKUN/local-ai-kit 下载到本地后，想连项目带它安装
       出来的东西一起删干净；
    2) 已经用向导/命令行装过，现在想完整卸载。

  特点：
    - 不依赖 Node.js（纯 Windows 自带命令），即使你把 Node 也一起卸了也能跑；
    - 删除前会把“要删什么 / 不删什么”列清楚，并逐项要求确认；
    - 模型目录（可能十几 GB）单独确认，且只在路径确实是 ollama\models 结构时才删；
    - 通用软件（Ollama、Node.js、dsh）默认不动，需你明确同意才卸载。

  用法：
    直接双击“彻底卸载本地AI.cmd”即可；
    也可以把项目文件夹拖到该 .cmd 上，或在命令行传路径：
       彻底卸载本地AI.cmd "D:\local-ai-kit"
  ============================================================================
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# ----- 颜色输出 -----
function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)       { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg)     { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Write-Skip($msg)     { Write-Host "    - $msg" -ForegroundColor Gray }
function Write-Danger($msg)   { Write-Host "    $msg" -ForegroundColor Red }

function Ask($q) {
    Write-Host $q -NoNewline -ForegroundColor White
    return (Read-Host).Trim()
}
function Confirm($q) {
    $a = Ask "$q (yes/是 回车确认，其它取消): "
    return ($a -match '^(y|yes|是|确认)$')
}

function Get-FreeGB($p) {
    try {
        $d = (Get-Item $p -ErrorAction SilentlyContinue).PSDrive
        if (-not $d) { $d = (Resolve-Path $p -ErrorAction SilentlyContinue).ProviderPath }
        $drv = Get-PSDrive -Name $d -ErrorAction SilentlyContinue
        if ($drv -and $drv.Free -ne $null) { return [math]::Round($drv.Free / 1GB, 1) }
    } catch {}
    return $null
}

# ----- 桌面真实路径（可能被重定向到 OneDrive 等） -----
function Find-Desktop {
    if ($env:LOCALAI_DESKTOP -and (Test-Path $env:LOCALAI_DESKTOP)) { return $env:LOCALAI_DESKTOP }
    $probes = @(
        { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name Desktop -ErrorAction SilentlyContinue).Desktop },
        { Join-Path $env:USERPROFILE 'OneDrive\Desktop' },
        { Join-Path $env:USERPROFILE 'OneDrive - Personal\Desktop' },
        { Join-Path $env:USERPROFILE 'Desktop' }
    )
    foreach ($p in $probes) {
        try { $r = & $p; if ($r -and (Test-Path $r)) { return $r } } catch {}
    }
    return Join-Path $env:USERPROFILE 'Desktop'
}

# ----- 判断某文件夹是不是 local-ai-kit 相关（下载源 或 安装目录） -----
function Test-IsKit($dir) {
    if (-not $dir -or -not (Test-Path $dir)) { return $false }
    $hasScriptsInstall = Test-Path (Join-Path $dir 'scripts\install.mjs')
    $hasRootInstall   = Test-Path (Join-Path $dir 'install.mjs')
    $hasConfigJson    = Test-Path (Join-Path $dir '配置.json')
    $hasUi            = Test-Path (Join-Path $dir 'ui')
    # 下载源：scripts\install.mjs 必然存在
    if ($hasScriptsInstall) { return $true }
    # 安装目录：install.mjs 被平铺到根，并带 配置.json 或 ui
    if ($hasRootInstall -and ($hasConfigJson -or $hasUi)) { return $true }
    return $false
}

# ----- 探测所有 local-ai-kit 相关目录（下载源 + 安装目录） -----
function Find-KitCandidates {
    $found = @()
    $seen = @{}
    $roots = @()

    # 用户常见目录
    $roots += @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Pictures'),
        (Join-Path $env:USERPROFILE 'Music'),
        (Join-Path $env:USERPROFILE 'Videos'),
        $PSScriptRoot
    )
    # 各盘根目录
    Get-PSDrive -PSProvider FileSystem | ForEach-Object { $roots += $_.Root }

    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        # 根目录本身
        if (Test-IsKit $root) { Add-Candidate $root }
        # 根目录下一级（深度 1，避免全盘慢扫）
        try {
            Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\.' } | ForEach-Object {
                if (Test-IsKit $_.FullName) { Add-Candidate $_.FullName }
            }
        } catch {}
    }

    function Add-Candidate($p) {
        $k = $p.ToLower()
        if (-not $seen[$k]) { $seen[$k] = $true; $script:found += $p }
    }
    return $found
}

# ----- 按端口结束进程 -----
function Stop-Port($port) {
    $pids = @()
    try {
        Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { $pids += $_.OwningProcess }
    } catch {}
    # 兜底：netstat
    if (-not $pids.Count) {
        netstat -ano -p TCP 2>$null | Select-String "127\.0\.0\.1:$port\s+.+LISTENING\s+(\d+)" | ForEach-Object {
            if ($_.Matches[0].Groups[1].Value) { $pids += $_.Matches[0].Groups[1].Value }
        }
    }
    $pids = $pids | Where-Object { $_ -and $_ -ne 0 } | Sort-Object -Unique
    foreach ($pid in $pids) {
        try { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; Write-OK "已结束占用端口 $port 的进程 (PID $pid)" } catch {}
    }
    return $pids.Count
}

function Stop-Ollama {
    $imgs = @('ollama app.exe', 'ollama.exe')
    foreach ($img in $imgs) {
        try { taskkill /IM "$img" /F /T 2>$null | Out-Null } catch {}
    }
}

# ----- 删除桌面快捷方式 -----
function Remove-Shortcuts {
    $desktop = Find-Desktop
    $names = @('启动本地AI.lnk', '停止本地AI.lnk', '本地AI控制台.lnk', '本地AI卸载.lnk')
    $n = 0
    foreach ($name in $names) {
        $p = Join-Path $desktop $name
        if (Test-Path $p) {
            try { Remove-Item $p -Force; Write-OK "已删除桌面快捷方式：$name"; $n++ } catch { Write-Warn "删除失败：$name" }
        }
    }
    if (-not $n) { Write-Skip '未找到 local-ai-kit 的桌面快捷方式。' }
    return $n
}

# ----- 清用户环境变量 OLLAMA_* -----
function Remove-EnvVars {
    $vars = @('OLLAMA_MODELS', 'OLLAMA_CONTEXT_LENGTH', 'OLLAMA_FLASH_ATTENTION',
             'OLLAMA_KV_CACHE_TYPE', 'OLLAMA_KEEP_ALIVE', 'OLLAMA_HOST')
    $n = 0
    foreach ($v in $vars) {
        try {
            $cur = (Get-ItemProperty 'HKCU:\Environment' -Name $v -ErrorAction SilentlyContinue).$v
            if ($null -ne $cur) {
                Remove-ItemProperty 'HKCU:\Environment' -Name $v -ErrorAction SilentlyContinue
                Write-OK "已删除环境变量 $v = $cur"
                $n++
            }
        } catch {}
    }
    if (-not $n) { Write-Skip '没有需要清理的 OLLAMA_* 用户环境变量。' }
    return $n
}

function Remove-TempLog {
    $log = Join-Path $env:TEMP 'localai-setup.log'
    if (Test-Path $log) {
        try { Remove-Item $log -Force; Write-OK "已删除安装日志：$log" } catch { Write-Warn "删除日志失败：$log" }
    } else { Write-Skip '未找到安装日志。' }
}

# ----- 找模型目录（ollama\models） -----
function Find-ModelDirs {
    $dirs = @()
    $seen = @{}
    if ($env:OLLAMA_MODELS -and (Test-Path $env:OLLAMA_MODELS)) { $dirs += $env:OLLAMA_MODELS }
    $dirs += Join-Path $env:USERPROFILE '.ollama\models'
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $dirs += Join-Path $_.Root 'ollama\models'
    }
    $dirs = $dirs | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
    return $dirs
}

function Remove-Models {
    $dirs = Find-ModelDirs
    if (-not $dirs.Count) { Write-Skip '未找到 ollama 模型目录。'; return }
    foreach ($d in $dirs) {
        # 安全阀：只删确实是 ...\ollama\models 结构的目录
        if ($d -notmatch '[\\/]ollama[\\/]models[\\/]?$') {
            Write-Warn "路径 $d 不是标准 ollama\models 结构，为安全起见跳过（请手动处理）。"
            continue
        }
        $free = Get-FreeGB $d
        $size = $null
        try { $size = [math]::Round((Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 1) } catch {}
        Write-Warn "发现模型目录：$d" + $(if ($size) { " (约 $size GB)" } else { '' })
        if (Confirm "    确定连模型一起删除吗？这会释放大量空间。") {
            try { Remove-Item $d -Recurse -Force; Write-OK '模型目录已删除。' } catch { Write-Danger '删除失败，可能被占用，请关闭 Ollama 后手动删除。' }
        } else { Write-Skip '已保留模型目录。' }
    }
}

# ----- 卸载 Ollama（可选） -----
function Uninstall-Ollama {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\unins000.exe'),
        'C:\Program Files\Ollama\unins000.exe'
    )
    $un = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $un) { Write-Skip '未找到 Ollama 卸载程序（可能本就不是它装的）。可到“设置→应用”手动卸载。'; return }
    Write-Warn "找到 Ollama 卸载程序：$un"
    if (Confirm '    要启动 Ollama 卸载程序吗？（会弹出确认窗口）') {
        try { Start-Process $un '/SILENT' -Wait; Write-OK 'Ollama 卸载程序已执行。' } catch { Write-Warn '启动失败，请到“设置→应用”手动卸载 Ollama。' }
    } else { Write-Skip '已保留 Ollama。' }
}

# ----- 卸载 Node.js（可选，仅当是 kit 自动装的 msi 版） -----
function Uninstall-Node {
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $node = $null
    foreach ($k in $keys) {
        try {
            Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -match '^Node\.js' -and $_.UninstallString -match 'msiexec'
            } | ForEach-Object { if (-not $node) { $node = $_ } }
        } catch {}
    }
    if (-not $node) { Write-Skip '未在注册表找到 Node.js 的 msi 安装记录。'; return }
    Write-Warn "找到 Node.js 安装记录：$($node.DisplayName)"
    if (Confirm '    要卸载 Node.js 吗？（一般不需要，可能影响其它项目）') {
        $guid = [regex]::Match($node.UninstallString, '\{[^}]+\}').Value
        if ($guid) {
            try { Start-Process 'msiexec.exe' "/x $guid /qb" -Wait; Write-OK 'Node.js 卸载已执行。' } catch { Write-Warn 'Node.js 卸载失败，请到“设置→应用”手动卸载。' }
        } else { Write-Warn '未能解析卸载命令，请手动卸载 Node.js。' }
    } else { Write-Skip '已保留 Node.js。' }
}

# ----- 清理开机自启项（仅明显属于本工具的） -----
function Remove-StartupEntries {
    $patterns = @('ollama', 'localai', 'local-ai', 'start-ai', 'dsh', 'deepseek')
    $locations = @()
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        Get-ItemProperty $runKey -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | ForEach-Object {
            $name = $_.Name
            if ($name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { return }
            $val = (Get-ItemProperty $runKey -Name $name -ErrorAction SilentlyContinue).$name
            if ($val -and ($patterns | Where-Object { $val -match $_ })) {
                $locations += [pscustomobject]@{ Kind = 'Registry'; Name = $name; Value = $val }
            }
        }
    } catch {}
    $startupFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    if (Test-Path $startupFolder) {
        Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | Where-Object {
            $patterns | Where-Object { $_.Name -match $_ }
        } | ForEach-Object { $locations += [pscustomobject]@{ Kind = 'StartupFolder'; Name = $_.Name; Value = $_.FullName } }
    }
    if (-not $locations.Count) { Write-Skip '未发现明显的本工具开机自启项。'; return }
    foreach ($loc in $locations) {
        Write-Warn "发现开机自启项 [$($loc.Kind)] $($loc.Name) -> $($loc.Value)"
        if (Confirm '    删除这个开机自启项吗？') {
            try {
                if ($loc.Kind -eq 'Registry') { Remove-ItemProperty $runKey -Name $loc.Name -ErrorAction SilentlyContinue; Write-OK "已删除注册表项：$($loc.Name)" }
                else { Remove-Item $loc.Value -Force; Write-OK "已删除：$($loc.Name)" }
            } catch { Write-Warn '删除失败。' }
        } else { Write-Skip "已保留：$($loc.Name)" }
    }
}

# ----- 卸载全局 dsh（可选） -----
function Remove-Dsh {
    try {
        $out = & node -v 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Skip '未检测到 node，跳过 dsh 检查。'; return }
        $list = & npm ls -g @deepseek-ai/dsh 2>$null
        if ($list -match 'deepseek') {
            Write-Warn '检测到全局安装的 @deepseek-ai/dsh（DeepSeek Harness 工作台）。'
            if (Confirm '    要卸载它吗？') {
                & npm uninstall -g @deepseek-ai/dsh 2>$null
                Write-OK 'dsh 卸载命令已执行。'
            } else { Write-Skip '已保留 dsh。' }
        } else { Write-Skip '未检测到全局 dsh。' }
    } catch { Write-Skip 'dsh 检查跳过。' }
}

# ----- 删除 local-ai-kit 目录 -----
function Remove-KitFolders($folders) {
    foreach ($f in $folders) {
        if (-not (Test-Path $f)) { continue }
        Write-Warn "即将删除目录：$f"
        try { Remove-Item $f -Recurse -Force -ErrorAction Stop; Write-OK "已删除：$f" }
        catch {
            Write-Danger "直接删除失败（可能有文件被占用），尝试以延迟方式删除…"
            # 延迟删除，绕开自身/占用
            $cmd = "timeout /t 3 /nobreak >nul & rmdir /s /q `"$f`""
            try { Start-Process 'cmd.exe' -ArgumentList "/c", $cmd -WindowStyle Hidden; Write-OK "已安排 3 秒后删除：$f" }
            catch { Write-Danger "自动删除失败，请手动删除：$f" }
        }
    }
}

# ============================================================================
#  主流程
# ============================================================================
Clear-Host
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '        local-ai-kit（本地 AI 部署包）彻底卸载工具' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '  本工具会尽量清理该部署包在本机留下的所有痕迹。' -ForegroundColor White
Write-Host '  删除前会逐项列出并询问确认，请看清再回车。' -ForegroundColor White
Write-Host ''

# 1) 确定要清理的目录
$candidates = @()
if ($args.Count -and (Test-Path $args[0])) {
    if (Test-IsKit $args[0]) { $candidates += $args[0] }
    else { Write-Warn "传入的路径不是 local-ai-kit 目录，仅作参考：$args[0]" }
}
$candidates += Find-KitCandidates
$candidates = $candidates | Sort-Object -Unique

if ($candidates.Count) {
    Write-Host '  自动找到以下 local-ai-kit 相关目录：' -ForegroundColor White
    $candidates | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
} else {
    Write-Warn '未自动找到 local-ai-kit 目录。'
}
Write-Host ''
$extra = Ask '  请输入项目/安装目录路径（可多个，用分号隔开；直接回车跳过/用上面自动找到的）：'
if ($extra.Trim()) {
    $extra.Split(';') | ForEach-Object {
        $p = $_.Trim().Trim('"')
        if ($p -and (Test-Path $p)) { $candidates += $p }
        elseif ($p) { Write-Warn "路径不存在，忽略：$p" }
    }
    $candidates = $candidates | Sort-Object -Unique
}

if (-not $candidates.Count) {
    Write-Danger '没有任何要删除的 local-ai-kit 目录。仍会继续清理快捷方式 / 环境变量 / 服务等。'
}

# 2) 总览
Write-Host ''
Write-Host '  将执行以下清理（具体以你的确认为准）：' -ForegroundColor White
Write-Host '    1) 停止 Ollama / 工作台 / 控制台 服务（端口 11434 / 3080 / 7790）' -ForegroundColor Gray
Write-Host '    2) 删除桌面快捷方式（启动/停止/控制台/卸载）' -ForegroundColor Gray
Write-Host '    3) 清理 OLLAMA_* 用户环境变量' -ForegroundColor Gray
Write-Host '    4) 删除安装日志 %TEMP%\localai-setup.log' -ForegroundColor Gray
Write-Host '    5) 删除 local-ai-kit 目录（下载源 + 安装目录）' -ForegroundColor Gray
Write-Host '    -- 以下为“可选/危险”项，会单独再问你 --' -ForegroundColor DarkGray
Write-Host '    6) 删除 Ollama 模型目录（可能十几 GB）' -ForegroundColor DarkGray
Write-Host '    7) 卸载 Ollama / Node.js / 全局 dsh / 开机自启项' -ForegroundColor DarkGray
Write-Host ''

if (-not (Confirm '  确认开始卸载吗？')) {
    Write-Host "`n  已取消，未删除任何内容。" -ForegroundColor Green
    exit 0
}

# 3) 执行
Write-Step '1/7' '停止服务…'
$null = Stop-Port 11434; Stop-Ollama
$null = Stop-Port 3080
$null = Stop-Port 7790
1..9 | ForEach-Object { $null = Stop-Port (7790 + $_) }
Write-OK '服务已尝试停止。'

Write-Step '2/7' '删除桌面快捷方式…'
$null = Remove-Shortcuts

Write-Step '3/7' '清理 OLLAMA_* 用户环境变量…'
$null = Remove-EnvVars

Write-Step '4/7' '删除安装日志…'
Remove-TempLog

Write-Step '5/7' '删除 local-ai-kit 目录…'
Remove-KitFolders $candidates

Write-Step '6/7' 'Ollama 模型目录…'
Remove-Models

Write-Step '7/7' '可选：Ollama / Node.js / dsh / 开机自启…'
Remove-StartupEntries
Uninstall-Ollama
Uninstall-Node
Remove-Dsh

# 4) 完成
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  清理完成。' -ForegroundColor Green
Write-Host '  提示：' -ForegroundColor White
Write-Host '    - 若某些目录几秒后仍未消失，可能是被占用，稍后手动删除即可；' -ForegroundColor Gray
Write-Host '    - 若你之后重装，重新运行安装向导即可。' -ForegroundColor Gray
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Ask '按回车退出…' | Out-Null
