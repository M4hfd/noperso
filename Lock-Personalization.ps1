#Requires -RunAsAdministrator
<#
  Блокировка персонализации Windows для студентов.

  Запуск (от администратора):
    powershell -ExecutionPolicy Bypass -File .\Lock-Personalization.ps1
  Откат:
    powershell -ExecutionPolicy Bypass -File .\Lock-Personalization.ps1 -Undo
  Исключить учётки администраторов:
    ... -ExcludeUsers 'Administrator','itadmin'
#>
param(
    [string[]]$ExcludeUsers = @('Administrator', 'admin'),
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'

# ---------- Машинные политики (HKLM, действуют на всех) ----------
$machine = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
       Name = 'SettingsPageVisibility'; Type = 'String'
       Value = 'hide:personalization;personalization-background;personalization-colors;lockscreen;themes;taskbar;personalization-start;fonts' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
       Name = 'NoChangingLockScreen'; Type = 'DWord'; Value = 1 }
)

foreach ($m in $machine) {
    if ($Undo) {
        if (Test-Path $m.Path) { Remove-ItemProperty $m.Path -Name $m.Name -ErrorAction SilentlyContinue }
    } else {
        New-Item $m.Path -Force | Out-Null
        Set-ItemProperty $m.Path -Name $m.Name -Value $m.Value -Type $m.Type
    }
}

# ---------- Пользовательские политики (HKCU каждого профиля) ----------
$base = 'Software\Microsoft\Windows\CurrentVersion\Policies'
$user = @(
    @{ Sub = "$base\ActiveDesktop"; Name = 'NoChangingWallPaper' },
    @{ Sub = "$base\Explorer";      Name = 'NoThemesTab' },
    @{ Sub = "$base\Explorer";      Name = 'NoDispCPL' },
    @{ Sub = "$base\Explorer";      Name = 'NoSetTaskbar' },
    @{ Sub = "$base\Explorer";      Name = 'LockTaskbar' },
    @{ Sub = "$base\System";        Name = 'NoDispAppearancePage' },
    @{ Sub = "$base\System";        Name = 'NoDispBackgroundPage' },
    @{ Sub = "$base\System";        Name = 'NoDispScrSavPage' }
)

function Set-UserPolicies([string]$Root) {
    foreach ($i in $user) {
        $key = "$Root\$($i.Sub)"
        if ($Undo) {
            if (Test-Path $key) { Remove-ItemProperty $key -Name $i.Name -ErrorAction SilentlyContinue }
        } else {
            New-Item $key -Force | Out-Null
            Set-ItemProperty $key -Name $i.Name -Value 1 -Type DWord
        }
    }
}

function Invoke-WithHive([string]$Name, [string]$File) {
    reg load "HKU\$Name" $File | Out-Null
    try { Set-UserPolicies "Registry::HKEY_USERS\$Name" }
    finally {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        reg unload "HKU\$Name" | Out-Null
    }
}

# Существующие профили
Get-CimInstance Win32_UserProfile |
    Where-Object { -not $_.Special -and $_.LocalPath } |
    ForEach-Object {
        $name = Split-Path $_.LocalPath -Leaf
        if ($ExcludeUsers -contains $name) { Write-Host "Пропуск: $name"; return }
        $sid = $_.SID
        Write-Host "Профиль: $name"
        if (Test-Path "Registry::HKEY_USERS\$sid") {
            Set-UserPolicies "Registry::HKEY_USERS\$sid"          # пользователь сейчас вошёл
        } else {
            Invoke-WithHive "TMP_$sid" (Join-Path $_.LocalPath 'NTUSER.DAT')
        }
    }

# Шаблон для новых профилей (Default User)
Write-Host 'Шаблон новых профилей (Default)'
Invoke-WithHive 'TMP_Default' 'C:\Users\Default\NTUSER.DAT'

Write-Host 'Готово. Студентам нужно выйти и войти заново.'
