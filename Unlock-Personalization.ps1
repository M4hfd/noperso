#Requires -RunAsAdministrator
<#
  Откат блокировки персонализации Windows (парный к Lock-Personalization.ps1).

  Запуск (от администратора):
    powershell -ExecutionPolicy Bypass -File .\Unlock-Personalization.ps1
  Откат только для части учётных записей:
    ... -OnlyUsers 'student1','student2'
#>
param(
    [string[]]$OnlyUsers = @()   # пусто = все профили
)

$ErrorActionPreference = 'Stop'

# ---------- Машинные политики (HKLM) ----------
$machine = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'SettingsPageVisibility' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization';        Name = 'NoChangingLockScreen' }
)

foreach ($m in $machine) {
    if (Test-Path $m.Path) {
        Remove-ItemProperty $m.Path -Name $m.Name -ErrorAction SilentlyContinue
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

function Remove-UserPolicies([string]$Root) {
    foreach ($i in $user) {
        $key = "$Root\$($i.Sub)"
        if (Test-Path $key) {
            Remove-ItemProperty $key -Name $i.Name -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WithHive([string]$Name, [string]$File) {
    reg load "HKU\$Name" $File | Out-Null
    try { Remove-UserPolicies "Registry::HKEY_USERS\$Name" }
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
        if ($OnlyUsers.Count -gt 0 -and $OnlyUsers -notcontains $name) { return }
        $sid = $_.SID
        Write-Host "Профиль: $name"
        if (Test-Path "Registry::HKEY_USERS\$sid") {
            Remove-UserPolicies "Registry::HKEY_USERS\$sid"       # пользователь сейчас вошёл
        } else {
            Invoke-WithHive "TMP_$sid" (Join-Path $_.LocalPath 'NTUSER.DAT')
        }
    }

# Шаблон для новых профилей (Default User)
if ($OnlyUsers.Count -eq 0) {
    Write-Host 'Шаблон новых профилей (Default)'
    Invoke-WithHive 'TMP_Default' 'C:\Users\Default\NTUSER.DAT'
}

Write-Host 'Готово. Пользователям нужно выйти и войти заново.'
