<#
  devmaru — Windows 11 + WSL2 준비 스크립트 (실험적 지원)

  하는 일(Windows 쪽 준비만): WSL distro(Ubuntu 26.04) 설치 · 부팅 때 distro 를 켜 두는 작업 · 외부(LAN) 접속 설정 · 방화벽 규칙.
  devmaru 자체는 이 스크립트가 끝난 뒤 distro 안에서 설치합니다(docs/INSTALL.md).

  사용(관리자 PowerShell — 파란 «Windows PowerShell» 5.1 또는 PowerShell 7):
    .\install-windows.ps1                 계획만 보여 줍니다(아무것도 바꾸지 않습니다)
    .\install-windows.ps1 -Apply          실제로 적용합니다
    .\install-windows.ps1 -Uninstall -Apply [-RemoveDistro] [-Yes]   이 스크립트가 만든 것을 되돌립니다

  주요 옵션
    -Distro   Ubuntu-26.04 (기본)
    -Network  mirrored(기본: Windows 11 22H2 이상, 포트 전달 없이 LAN 에서 바로 접속) | portproxy(포트 전달 + IP 갱신 작업)
    -SshPort  회원 SSH 포트(기본 2222 — Windows OpenSSH 가 22 를 쓰므로 22 는 쓰지 않습니다). -NoMemberSsh 면 설정하지 않습니다

  시험한 범위: Windows 11 Pro 10.0.26300 · WSL 2.7.3 한 대. 자동 로그인이 꺼진 PC, 다른 Windows 빌드는 시험하지 않았습니다.
#>
[CmdletBinding()]
param(
  [string]$Distro = "Ubuntu-26.04",
  [ValidateSet("mirrored", "portproxy")][string]$Network = "mirrored",
  [int]$SshPort = 2222,
  [switch]$NoMemberSsh,
  [switch]$Apply,
  [switch]$Uninstall,
  [switch]$RemoveDistro,
  [switch]$Yes
)
$ErrorActionPreference = "Stop"
$KeepTask = "devmaru-wsl-keepalive"
$ProxyTask = "devmaru-wsl-portproxy"
$FwWeb = "devmaru-web-lan"
$FwSsh = "devmaru-ssh-lan"
$DataDir = Join-Path $env:ProgramData "devmaru"
$WslCfg = Join-Path $env:USERPROFILE ".wslconfig"
$WslCfgBak = "$WslCfg.bak.pre-devmaru"

function Say($m) { Write-Host $m }
function Step($desc, [scriptblock]$act) {
  if ($Apply) { Say "▶ $desc"; & $act } else { Say "· (계획) $desc" }
}
function Wsl-Root([string]$cmd) { & wsl.exe -d $Distro -u root -- bash -c $cmd }
function Distro-Installed {
  $l = ((& wsl.exe -l -q 2>$null) | Out-String) -replace "`0", ""
  return [bool]($l -match "(?m)^\s*$([regex]::Escape($Distro))\s*$")
}
function Distro-Running {
  $l = ((& wsl.exe -l --running -q 2>$null) | Out-String) -replace "`0", ""
  return [bool]($l -match "(?m)^\s*$([regex]::Escape($Distro))\s*$")
}

# --- 사전 확인 ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Apply -and -not $isAdmin) { throw "관리자 권한 PowerShell 에서 실행하세요(시작 메뉴 → PowerShell → 관리자 권한으로 실행)." }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw "wsl.exe 가 없습니다. Windows 11 에서 'wsl --install' 로 WSL 을 먼저 설치하세요." }
$build = [Environment]::OSVersion.Version.Build
if ($Network -eq "mirrored" -and $build -lt 22621) { throw "mirrored 네트워킹은 Windows 11 22H2(빌드 22621) 이상이 필요합니다(현재 빌드 $build). -Network portproxy 를 쓰세요." }
$me = (whoami)
Say "== devmaru Windows 준비 ($(if ($Uninstall) { '되돌리기' } else { '설치' })) — distro=$Distro network=$Network 계정=$me 빌드=$build =="
if (-not $Apply) { Say "   (계획만 보여 줍니다 — 실제로 적용하려면 -Apply)" }

# --- .wslconfig 의 [wsl2] 에 한 줄 넣기/빼기 ---
function Set-WslConfigKey([string]$key, [string]$value, [switch]$NoBackup) {
  $lines = if (Test-Path $WslCfg) { @(Get-Content $WslCfg) } else { @() }
  # 백업은 «설치로 처음 바꾸기 전» 한 번만(되돌리기 경로에서는 이미 바뀐 파일을 백업하지 않는다 — 그러면 되돌릴 때 바뀐 값이 복원된다)
  if (-not $NoBackup -and (Test-Path $WslCfg) -and -not (Test-Path $WslCfgBak)) { Copy-Item $WslCfg $WslCfgBak }
  if (-not ($lines -match '^\s*\[wsl2\]')) { $lines = @("[wsl2]") + $lines }
  $out = New-Object System.Collections.Generic.List[string]; $done = $false
  foreach ($l in $lines) {
    if ($l -match "^\s*$([regex]::Escape($key))\s*=") { if (-not $done -and $value) { $out.Add("$key=$value"); $done = $true }; continue }
    $out.Add($l)
    if (-not $done -and $value -and $l -match '^\s*\[wsl2\]') { $out.Add("$key=$value"); $done = $true }
  }
  Set-Content -Path $WslCfg -Value $out -Encoding ascii
}

if ($Uninstall) {
  Step "작업 삭제: $KeepTask, $ProxyTask" {
    foreach ($t in $KeepTask, $ProxyTask) { if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $t -Confirm:$false } }
  }
  Step "방화벽 규칙 삭제: $FwWeb, $FwSsh" {
    foreach ($r in $FwWeb, $FwSsh) { Remove-NetFirewallRule -Name $r -ErrorAction SilentlyContinue }
  }
  Step "portproxy 80/443/$SshPort 규칙 삭제(다른 규칙은 건드리지 않습니다)" {
    foreach ($p in 80, 443, $SshPort) { netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>&1 | Out-Null }
  }
  Step "스크립트 폴더 삭제: $DataDir" { if (Test-Path $DataDir) { Remove-Item $DataDir -Recurse -Force } }
  Step ".wslconfig 되돌리기(networkingMode 줄 제거 또는 백업 복원)" {
    if (Test-Path $WslCfgBak) { Copy-Item $WslCfgBak $WslCfg -Force; Remove-Item $WslCfgBak -Force } elseif (Test-Path $WslCfg) { Set-WslConfigKey "networkingMode" "" -NoBackup }
  }
  if ($RemoveDistro) {
    Step "distro 삭제($Distro) — 안의 모든 데이터(DB·회원 작업물·Docker 이미지)가 사라집니다" {
      if (Distro-Installed) {
        if (-not $Yes) { $a = Read-Host "정말 $Distro 를 삭제할까요? 이름을 그대로 입력하세요"; if ($a -ne $Distro) { Say "취소했습니다."; return } }
        & wsl.exe --terminate $Distro | Out-Null; & wsl.exe --unregister $Distro | Out-Null
      } else { Say "  distro 가 없어 건너뜀" }
    }
  } else { Say "· distro 는 그대로 둡니다(삭제하려면 -RemoveDistro)" }
  Step "WSL 재시작(설정 반영)" { & wsl.exe --shutdown }
  Say "== 완료 =="
  return
}

# --- 설치 ---
Step "distro 설치: wsl --install -d $Distro --no-launch (이미 있으면 건너뜀)" {
  if (-not (Distro-Installed)) { & wsl.exe --install -d $Distro --no-launch | Out-Null; if (-not (Distro-Installed)) { throw "distro 설치에 실패했습니다. 'wsl --list --online' 에서 이름을 확인하세요." } } else { Say "  이미 설치됨" }
}
Step "systemd 켜기(/etc/wsl.conf)" {
  Wsl-Root 'grep -q "^systemd=true" /etc/wsl.conf 2>/dev/null || printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf'
  & wsl.exe --terminate $Distro | Out-Null
}
if ($Network -eq "mirrored") {
  Step ".wslconfig 에 networkingMode=mirrored (기존 파일은 .wslconfig.bak.pre-devmaru 로 백업)" { Set-WslConfigKey "networkingMode" "mirrored" }
  Step "이전 portproxy 방식의 흔적 제거(작업 $ProxyTask · 포트 전달 규칙 80/443/$SshPort — mirrored 에서는 Windows 가 이 포트를 잡고 있으면 WSL 의 Caddy 가 뜨지 못합니다)" {
    if (Get-ScheduledTask -TaskName $ProxyTask -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $ProxyTask -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $ProxyTask -Confirm:$false }
    foreach ($p in 80, 443, $SshPort) { netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>&1 | Out-Null }
    Remove-Item (Join-Path $DataDir "wsl-portproxy.ps1") -Force -ErrorAction SilentlyContinue
  }
} else {
  Step ".wslconfig 에서 networkingMode 제거(portproxy 방식은 NAT 사용)" { Set-WslConfigKey "networkingMode" "" }
}
Step "부팅 때 distro 를 켜 두는 작업 등록: $KeepTask (wsl … sleep infinity, 시작 시 실행, 로그인 불필요한 S4U)" {
  $a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -u root -- sleep infinity"
  $t = New-ScheduledTaskTrigger -AtStartup
  $p = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Limited
  $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
  Register-ScheduledTask -TaskName $KeepTask -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
}
Step "방화벽 규칙(같은 LAN 에서만): 웹 80·443 → $FwWeb" {
  Remove-NetFirewallRule -Name $FwWeb -ErrorAction SilentlyContinue
  New-NetFirewallRule -Name $FwWeb -DisplayName "devmaru web (LAN only)" -Direction Inbound -Protocol TCP -LocalPort 80, 443 -RemoteAddress LocalSubnet -Action Allow | Out-Null
}
if (-not $NoMemberSsh) {
  Step "방화벽 규칙(같은 LAN 에서만): 회원 SSH $SshPort → $FwSsh" {
    Remove-NetFirewallRule -Name $FwSsh -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name $FwSsh -DisplayName "devmaru member ssh (LAN only)" -Direction Inbound -Protocol TCP -LocalPort $SshPort -RemoteAddress LocalSubnet -Action Allow | Out-Null
  }
  Step "distro 안 sshd 를 포트 $SshPort 로(IPv4 0.0.0.0 로 명시 — IPv6 와일드카드만 두면 mirrored 에서 LAN 에 노출되지 않습니다)" {
    Wsl-Root ("mkdir -p /etc/systemd/system/ssh.socket.d /etc/ssh/sshd_config.d && printf '[Socket]\nListenStream=\nListenStream=0.0.0.0:$SshPort\n' > /etc/systemd/system/ssh.socket.d/listen.conf && printf 'Port $SshPort\n' > /etc/ssh/sshd_config.d/20-devmaru-wsl-port.conf")
  }
}
if ($Network -eq "portproxy") {
  Step "포트 전달 갱신 스크립트와 작업 등록: $ProxyTask (시작 시 + 5분마다 WSL IP 를 읽어 80·443과 회원 SSH 포트의 대상을 맞춤)" {
    New-Item -ItemType Directory -Force $DataDir | Out-Null
    $fwd = @(80, 443); if (-not $NoMemberSsh) { $fwd += $SshPort }
    $script = @'
param([string]$Distro = "__DISTRO__", [int[]]$Ports = @(__PORTS__))
$running = ((wsl.exe -l --running -q 2>$null) | Out-String) -replace "`0",""
if ($running -notmatch [regex]::Escape($Distro)) { exit 0 }
$out = (wsl.exe -d $Distro -u root -- hostname -I 2>$null | Out-String)
$ip = [regex]::Match($out, '\d+\.\d+\.\d+\.\d+').Value
if (-not $ip) { exit 1 }
$cur = netsh interface portproxy show v4tov4 | Out-String
foreach ($p in $Ports) {
  if ($cur -match "(?m)^\s*0\.0\.0\.0\s+$p\s+$([regex]::Escape($ip))\s+$p\s*$") { continue }
  netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 | Out-Null
  netsh interface portproxy add v4tov4 listenport=$p listenaddress=0.0.0.0 connectport=$p connectaddress=$ip | Out-Null
}
'@
    Set-Content -Path (Join-Path $DataDir "wsl-portproxy.ps1") -Value $script.Replace("__DISTRO__", $Distro).Replace("__PORTS__", ($fwd -join ",")) -Encoding ascii
    $a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$DataDir\wsl-portproxy.ps1`""
    $t = New-ScheduledTaskTrigger -AtStartup
    $t.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)).Repetition
    $p = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable
    Register-ScheduledTask -TaskName $ProxyTask -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
  }
}
Step "WSL 재시작 → distro 켜기(작업 시작)" {
  & wsl.exe --shutdown; Start-Sleep -Seconds 5
  Start-ScheduledTask -TaskName $KeepTask
  for ($i = 0; $i -lt 30 -and -not (Distro-Running); $i++) { Start-Sleep -Seconds 2 }
  if (-not (Distro-Running)) { Say "  경고: distro 가 아직 실행 중으로 보이지 않습니다(작업 상태: $((Get-ScheduledTask -TaskName $KeepTask).State))" } else { Say "  distro 실행 중" }
  if ($Network -eq "portproxy") { Start-Sleep -Seconds 10; Start-ScheduledTask -TaskName $ProxyTask }
}

Say ""
Say "== Windows 쪽 준비가 끝났습니다. 다음은 distro 안에서 devmaru 설치 =="
Say "  1) wsl -d $Distro -u root                       (distro 로 들어갑니다)"
Say "  2) docs/INSTALL.md 의 순서로 devmaru 를 설치합니다(한 줄 설치 또는 devmaru-install)."
Say "     - 설정 파일에는 SSH_PORT=$SshPort 를 쓰고, 공인 도메인이 없으면 TLS_MODE=internal"
Say "     - 외부(LAN)에서 접속할 주소는 이 PC 의 LAN IP 입니다(mirrored 면 그대로, portproxy 면 80·443 이 이 PC 로 전달됩니다)"
Say "  되돌리기: .\install-windows.ps1 -Uninstall -Apply  (distro 까지 지우려면 -RemoveDistro)"
