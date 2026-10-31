@echo off
rem ===========================================================================
rem  Minecraft Bedrock - Setup and Online Play Doctor
rem  ---------------------------------------------------------------------------
rem  Checks and repairs a GENUINE copy of Minecraft for Windows that you own
rem  and downloaded from the Microsoft Store / Xbox app.
rem
rem  It does NOT crack, patch, unlock or bypass licensing, and it does not ship
rem  any "online fix" binary. Online play in Minecraft Bedrock is tied to a real
rem  Microsoft account that owns the game, so the only way to "make it the full
rem  game with online working" is to own it and let the Store deliver it.
rem
rem  Run:  right click -> Run as administrator  (or just double click;
rem        the tool offers to elevate itself).
rem ===========================================================================

setlocal
title Minecraft Bedrock - Setup and Online Play Doctor
color 0F

set "MB_SELF=%~f0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo  PowerShell was not found on this PC. This tool needs it.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MB_SELF);$m='#:PS'+'START';$i=$s.IndexOf($m);if($i -lt 0){Write-Host 'Internal error: script block not found. Re-download the file.' -ForegroundColor Red;exit 1};try{Invoke-Expression $s.Substring($i+$m.Length)}catch{Write-Host '';Write-Host ('Startup error: '+$_.Exception.Message) -ForegroundColor Red}"

rem keep the window visible when the file was double-clicked
echo.
echo   Press any key to close this window . . .
pause >nul

rem nothing below this line is read by cmd.exe
exit /b
#:PSSTART

# ===========================================================================
#  PowerShell body. Everything below is executed by the line above.
# ===========================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$PkgName  = 'Microsoft.MinecraftUWP'
$StoreId  = '9NBLGGH2JHXJ'                                       # Minecraft for Windows
$StoreUrl = 'ms-windows-store://pdp/?productid=' + $StoreId
$WebUrl   = 'https://apps.microsoft.com/detail/' + $StoreId
$SelfPath = $env:MB_SELF

$global:Report = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------------------
#  Output helpers
# ---------------------------------------------------------------------------

function Add-Report {
    param([string]$Line)
    $global:Report.Add($Line) | Out-Null
}

function Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkCyan
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkCyan
    Add-Report ''
    Add-Report ('== ' + $Text + ' ==')
}

function OK {
    param([string]$Text)
    Write-Host ('  [ OK ]  ' + $Text) -ForegroundColor Green
    Add-Report ('OK   ' + $Text)
}

function Info {
    param([string]$Text)
    Write-Host ('  [INFO]  ' + $Text) -ForegroundColor Gray
    Add-Report ('INFO ' + $Text)
}

function Warn {
    param([string]$Text)
    Write-Host ('  [WARN]  ' + $Text) -ForegroundColor Yellow
    Add-Report ('WARN ' + $Text)
}

function Fail {
    param([string]$Text)
    Write-Host ('  [FAIL]  ' + $Text) -ForegroundColor Red
    Add-Report ('FAIL ' + $Text)
}

function Fixed {
    param([string]$Text)
    Write-Host ('  [FIX ]  ' + $Text) -ForegroundColor Magenta
    Add-Report ('FIX  ' + $Text)
}

function Pause-Script {
    Write-Host ''
    Read-Host '  Press Enter to return to the menu' | Out-Null
}

# ---------------------------------------------------------------------------
#  Environment helpers
# ---------------------------------------------------------------------------

function Test-Admin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-DesktopPath {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { $desktop = $env:USERPROFILE }
    return $desktop
}

function Get-SystemFacts {
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = 0
    $ubr = 0
    if ($cv) {
        if ($cv.CurrentBuildNumber) { $build = [int]$cv.CurrentBuildNumber }
        if ($cv.UBR) { $ubr = [int]$cv.UBR }
    }
    $name = 'Windows'
    if ($cv -and $cv.ProductName) { $name = $cv.ProductName }
    if ($build -ge 22000) { $name = 'Windows 11' }
    return [pscustomobject]@{
        Name  = $name
        Build = $build
        UBR   = $ubr
        Arch  = $env:PROCESSOR_ARCHITECTURE
        Admin = (Test-Admin)
    }
}

function Get-GamePackage {
    $pkg = $null
    try { $pkg = Get-AppxPackage -Name $PkgName -ErrorAction Stop | Select-Object -First 1 } catch { }
    if (-not $pkg -and (Test-Admin)) {
        try { $pkg = Get-AppxPackage -Name $PkgName -AllUsers -ErrorAction Stop | Select-Object -First 1 } catch { }
    }
    return $pkg
}

function Test-Package {
    param([string]$Name)
    try {
        $p = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
        if ($p) { return $true }
        return $false
    } catch {
        return $false
    }
}

$global:XboxServices = @(
    @{ Name = 'XblAuthManager';    Desc = 'Xbox Live Auth Manager' },
    @{ Name = 'XboxNetApiSvc';     Desc = 'Xbox Live Networking Service' },
    @{ Name = 'XblGameSave';       Desc = 'Xbox Live Game Save' },
    @{ Name = 'XboxGipSvc';        Desc = 'Xbox Accessory Management' },
    @{ Name = 'GamingServices';    Desc = 'Gaming Services' },
    @{ Name = 'GamingServicesNet'; Desc = 'Gaming Services Networking' }
)

# ---------------------------------------------------------------------------
#  Network probes
# ---------------------------------------------------------------------------

function Test-DnsName {
    param([string]$Name)
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($Name)
        if ($addrs -and $addrs.Count -gt 0) { return $true }
        return $false
    } catch {
        return $false
    }
}

function Test-Tcp {
    param([string]$Name, [int]$Port, [int]$TimeoutMs = 4000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Name, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-GlobalIPv6 {
    $out = @()
    try {
        $out = @(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object {
            $_.IPAddress -notlike 'fe80*' -and
            $_.IPAddress -ne '::1' -and
            $_.AddressState -eq 'Preferred' -and
            $_.PrefixOrigin -ne 'WellKnown'
        })
    } catch { }
    return $out
}

function Get-TeredoState {
    $text = ''
    try { $text = ((netsh interface teredo show state) -join ' ') } catch { return 'unknown' }
    if ($text -match 'disabled')  { return 'disabled' }
    if ($text -match 'qualified') { return 'qualified' }
    if ($text -match 'dormant')   { return 'dormant' }
    if ($text -match 'offline')   { return 'offline' }
    if ($text -match 'client')    { return 'client' }
    return 'unknown'
}

function Get-TimeDeltaSeconds {
    try {
        $req = [System.Net.HttpWebRequest]::Create('https://login.live.com/')
        $req.Method = 'HEAD'
        $req.Timeout = 8000
        $resp = $req.GetResponse()
        $dateHeader = $resp.Headers['Date']
        $resp.Close()
        if (-not $dateHeader) { return -1 }
        $server = [DateTimeOffset]::Parse($dateHeader).UtcDateTime
        $local = (Get-Date).ToUniversalTime()
        return [int][Math]::Abs(($local - $server).TotalSeconds)
    } catch {
        return -1
    }
}

$global:HostPattern = 'xboxlive|xbox\.com|xboxservices|microsoft\.com|minecraft|mojang|live\.com|playfab|xboxablenetworks|msftconnecttest|msftncsi'

function Get-BlockedHostEntries {
    $path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $hits = @(Select-String -LiteralPath $path -Pattern $global:HostPattern -ErrorAction SilentlyContinue | Where-Object {
        $_.Line -notmatch '^\s*#' -and $_.Line.Trim() -ne ''
    })
    return $hits
}

# ---------------------------------------------------------------------------
#  Checks
# ---------------------------------------------------------------------------

function Show-Banner {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '    Minecraft Bedrock  -  Setup and Online Play Doctor' -ForegroundColor Cyan
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '    Checks and repairs a genuine Minecraft for Windows copy' -ForegroundColor DarkGray
    Write-Host '    installed from the Microsoft Store / Xbox app.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    This tool does not crack or unlock anything: online play' -ForegroundColor DarkGray
    Write-Host '    needs a real Microsoft account that owns the game.' -ForegroundColor DarkGray
}

function Invoke-SystemCheck {
    Head 'Windows'
    $facts = Get-SystemFacts
    Info ($facts.Name + ' build ' + $facts.Build + '.' + $facts.UBR + ' (' + $facts.Arch + ')')
    if ($facts.Build -lt 19041) {
        Fail 'Minecraft for Windows needs Windows 10 version 2004 (build 19041) or newer.'
        Info 'Update Windows first, then run this tool again.'
    } else {
        OK 'Windows version supports Minecraft for Windows'
    }
    if ($facts.Arch -eq 'ARM64') {
        Info 'ARM64 device: use the native ARM64 build from the Store (Windows 11).'
    }
    if ($facts.Admin) {
        Info 'Running as Administrator - repairs can be applied'
    } else {
        Warn 'Not running as Administrator - repairs will need elevation'
    }
    return $facts
}

function Invoke-GameCheck {
    Head 'Minecraft installation'
    $pkg = Get-GamePackage
    if (-not $pkg) {
        Fail 'Minecraft for Windows is not installed for this Windows user.'
        Info 'Use option 2 to open the official Microsoft Store page and install it.'
        return $pkg
    }

    OK ('Installed: version ' + $pkg.Version)
    Info ('Package: ' + $pkg.PackageFullName)
    Info ('Family : ' + $pkg.PackageFamilyName)

    if ($pkg.Status -eq 'Ok') {
        OK 'Package and Store license state: Ok'
    } else {
        Warn ('Package status: ' + $pkg.Status)
        Info 'A modified / re-packed copy cannot sign in to Xbox Live - online play fails.'
        Info 'Use option 6 to remove it and reinstall the official copy from the Store.'
    }

    if ($pkg.IsDevelopmentMode) {
        Warn 'Package is in development (sideloaded) mode - Store licensing and Xbox Live will not work.'
    }

    $version = [version]$pkg.Version
    if ($version -lt [version]'1.20.0.0') {
        Info 'This build is quite old. Updating from the Store fixes many connection bugs.'
    }

    return $pkg
}

function Invoke-ComponentCheck {
    Head 'Xbox components'
    if (Test-Package 'Microsoft.GamingServices')      { OK 'Gaming Services installed' }        else { Fail 'Gaming Services missing - install the Xbox app from the Store' }
    if (Test-Package 'Microsoft.XboxIdentityProvider') { OK 'Xbox Identity Provider installed' } else { Fail 'Xbox Identity Provider missing - Microsoft sign-in will fail' }
    if (Test-Package 'Microsoft.GamingApp')           { OK 'Xbox app installed' }               else { Warn 'Xbox app not found (recommended for sign-in and Xbox Live)' }
    if (Test-Package 'Microsoft.WindowsStore')        { OK 'Microsoft Store installed' }         else { Fail 'Microsoft Store missing - the game cannot be verified or updated' }
}

function Invoke-ServiceCheck {
    Head 'Xbox services'
    $stopped = 0
    foreach ($s in $global:XboxServices) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if (-not $svc) {
            Warn ($s.Desc + ' (' + $s.Name + ') is not installed')
            $stopped++
            continue
        }
        if ($svc.Status -eq 'Running') {
            OK ($s.Desc + ' is running')
        } else {
            Warn ($s.Desc + ' is ' + $svc.Status)
            $stopped++
        }
    }
    if ($stopped -eq 0) { OK 'All Xbox services look healthy' }
    return $stopped
}

function Invoke-NetworkCheck {
    Head 'Network and Xbox Live reachability'

    $names = @('microsoft.com', 'login.live.com', 'xboxlive.com', 'minecraft.net', 'api.minecraftservices.com')
    foreach ($n in $names) {
        if (Test-DnsName -Name $n) { OK ('DNS resolves: ' + $n) }
        else { Fail ('DNS does not resolve: ' + $n) }
    }

    if (Test-Tcp -Name 'login.live.com' -Port 443) { OK 'Microsoft account sign-in service reachable (TCP 443)' }
    else { Fail 'Cannot reach login.live.com:443 - sign-in will fail' }

    if (Test-Tcp -Name 'xboxlive.com' -Port 443) { OK 'Xbox Live reachable (TCP 443)' }
    else { Fail 'Cannot reach xboxlive.com:443 - online play will fail' }

    if (Test-Tcp -Name 'minecraft.net' -Port 443) { OK 'Minecraft services reachable (TCP 443)' }
    else { Fail 'Cannot reach minecraft.net:443' }

    $blocked = Get-BlockedHostEntries
    if ($blocked.Count -gt 0) {
        Fail ('The hosts file blocks ' + $blocked.Count + ' Microsoft / Xbox domain(s) - this breaks sign-in and online play')
        foreach ($b in $blocked) { Info ('  line ' + $b.LineNumber + ': ' + $b.Line.Trim()) }
        Info 'Use option 3 to remove them (a backup of the file is kept).'
    } else {
        OK 'No blocking entries in the hosts file'
    }

    $v6 = Get-GlobalIPv6
    if ($v6.Count -gt 0) { OK ('IPv6 available (' + $v6.Count + ' global address(es)) - best case for Xbox multiplayer') }
    else {
        Warn 'No global IPv6 address on this PC'
        Info ('Teredo state: ' + (Get-TeredoState) + ' (Xbox Live uses Teredo as the IPv4 fallback)')
        Info 'Option 3 can enable Teredo client mode.'
    }

    $proxy = $null
    try { $proxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue } catch { }
    if ($proxy -and $proxy.ProxyEnable -eq 1) {
        Warn ('A system proxy is enabled (' + $proxy.ProxyServer + ') - proxies commonly break Xbox Live')
    } else {
        OK 'No system proxy configured'
    }

    try {
        $vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'VPN|TAP|TUN|WireGuard|Tailscale|OpenVPN|NordLynx|Proton|WARP|ZeroTier|Hamachi'
        })
        if ($vpn.Count -gt 0) {
            $vpnNames = @($vpn | ForEach-Object { $_.Name })
            Warn ('A VPN / tunnel adapter is active (' + ($vpnNames -join ', ') + ') - disconnect it while playing')
        } else {
            OK 'No VPN or tunnel adapter active'
        }
    } catch { }

    $delta = Get-TimeDeltaSeconds
    if ($delta -lt 0) { Info 'Could not verify the system clock against Microsoft servers' }
    elseif ($delta -gt 300) { Warn ('System clock is off by about ' + $delta + ' seconds - certificate checks fail and sign-in breaks') }
    else { OK 'System clock is in sync' }

    try {
        $profs = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
        foreach ($p in $profs) {
            Info ('Network "' + $p.Name + '": ' + $p.NetworkCategory)
            if ($p.NetworkCategory -eq 'Public') {
                Warn 'A "Public" network profile is stricter; set it to Private on your home network'
            }
        }
    } catch { }
}

function Invoke-MultiplayerCheck {
    Head 'Multiplayer checklist (things only you can confirm)'
    Info 'Sign in with the SAME Microsoft account in the Xbox app, the Microsoft Store and Minecraft.'
    Info 'That account must own Minecraft for Windows - a trial does not allow online play.'
    Info 'In Minecraft: Settings > Profile shows whether you are signed in.'
    Info 'Windows Settings > Gaming > Xbox Networking should show NAT type Open or Moderate.'
    Info 'Xbox multiplayer uses UDP 88, 3074, 500, 3544 and 4500 - enable UPnP on your router if NAT is Strict.'
    Info 'A child account: the parent must allow multiplayer in the Microsoft family privacy settings.'
    Info 'Turn off VPNs, proxies and "gaming boosters" while playing.'
    Info 'LAN worlds need all PCs on the same network with the Private profile.'
}

function Invoke-FullCheck {
    $global:Report.Clear()
    $facts = Invoke-SystemCheck
    Invoke-GameCheck | Out-Null
    Invoke-ComponentCheck
    Invoke-ServiceCheck | Out-Null
    Invoke-NetworkCheck
    Invoke-MultiplayerCheck
    Head 'Summary'
    if ($facts.Build -ge 19041 -and $facts.Admin) {
        Info 'Option 3 applies the online-play fixes; option 7 saves this report.'
    } else {
        Info 'Fix anything marked FAIL or WARN with option 3, then re-run option 1.'
    }
    return $global:Report.Count
}

# ---------------------------------------------------------------------------
#  Repairs
# ---------------------------------------------------------------------------

function Repair-Services {
    $changed = 0
    foreach ($s in $global:XboxServices) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ($svc.Status -ne 'Running') {
            try {
                Start-Service -Name $s.Name -ErrorAction Stop
                Fixed ($s.Desc + ' started')
                $changed++
            } catch {
                Warn ('Could not start ' + $s.Desc + ': ' + $_.Exception.Message)
            }
        }
    }
    if ($changed -eq 0) { OK 'All available Xbox services were already running' }
}

function Repair-Teredo {
    $v6 = Get-GlobalIPv6
    if ($v6.Count -gt 0) {
        OK 'IPv6 is available - no Teredo fallback needed'
        return
    }
    $state = Get-TeredoState
    if ($state -eq 'qualified') {
        OK 'Teredo is qualified'
        return
    }
    Warn ('No IPv6 and Teredo state is: ' + $state)
    $ans = Read-Host '  Enable Teredo in client mode (IPv4 fallback for Xbox Live)? [Y/n]'
    if ($ans -match '^[nN]') { Info 'Skipped'; return }
    try {
        netsh interface teredo set state type=client | Out-Null
        Fixed 'Teredo enabled in client mode'
        Info 'Teredo can take a minute to become "qualified"; NAT type may read Strict until then.'
    } catch {
        Warn 'Could not change the Teredo state - run as Administrator'
    }
}

function Repair-HostsFile {
    $blocked = Get-BlockedHostEntries
    if ($blocked.Count -eq 0) {
        OK 'Hosts file does not block Microsoft / Xbox domains'
        return
    }
    Warn ('The hosts file blocks ' + $blocked.Count + ' Microsoft / Xbox / Minecraft domain(s)')
    foreach ($b in $blocked) { Info ('  line ' + $b.LineNumber + ': ' + $b.Line.Trim()) }
    $ans = Read-Host '  Remove those entries now (a backup is kept)? [y/N]'
    if ($ans -notmatch '^[yY]') { Info 'Skipped'; return }
    $path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $backup = $path + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    try {
        Copy-Item -LiteralPath $path -Destination $backup -Force -ErrorAction Stop
        $lines = Get-Content -LiteralPath $path -ErrorAction Stop
        $keep = @($lines | Where-Object {
            -not ( ($_ -notmatch '^\s*#') -and ($_ -match $global:HostPattern) )
        })
        Set-Content -LiteralPath $path -Value $keep -Encoding ASCII -Force -ErrorAction Stop
        Fixed ('Blocked entries removed - backup: ' + $backup)
    } catch {
        Warn ('Could not rewrite the hosts file: ' + $_.Exception.Message)
        Info ('Edit it manually with Notepad (as Administrator): ' + $path)
    }
}

function Repair-Firewall {
    $removed = 0
    try {
        $rules = @(Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match 'Minecraft'
        })
        foreach ($r in $rules) {
            try {
                Remove-NetFirewallRule -Name $r.Name -ErrorAction Stop
                Fixed ('Removed blocking firewall rule: ' + $r.DisplayName)
                $removed++
            } catch { }
        }
    } catch { }
    if ($removed -eq 0) { OK 'No Minecraft blocking firewall rules found' }

    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
        foreach ($p in $profiles) {
            if ($p.Enabled -and $p.DefaultOutboundAction -eq 'Block') {
                Warn ('Firewall profile ' + $p.Name + ' blocks outbound traffic by default - allow Minecraft')
            }
        }
    } catch { }
}

function Invoke-OnlineFix {
    if (-not (Test-Admin)) {
        Warn 'Repairs need Administrator rights.'
        Invoke-Elevate
        return
    }

    Head 'Applying online-play fixes'
    Repair-Services

    try { ipconfig /flushdns | Out-Null; Fixed 'DNS cache flushed' } catch { }

    Repair-Teredo
    Repair-HostsFile
    Repair-Firewall

    $delta = Get-TimeDeltaSeconds
    if ($delta -gt 300) {
        try {
            w32tm /resync /force | Out-Null
            Fixed 'System clock resynchronised'
        } catch {
            Warn 'Clock is off - click "Sync now" in Settings > Time and language'
        }
    } elseif ($delta -ge 0) {
        OK 'System clock is in sync'
    }

    Head 'Next steps'
    Info 'Fully quit Minecraft (Xbox app > Minecraft > Quit) and start it again.'
    Info 'If NAT type is still Strict, forward UDP 88/3074/500/3544/4500 or enable UPnP.'
    Info 'Still broken? Run option 1 again - the report shows exactly what is blocked.'

    $ans = Read-Host '  Open Settings > Gaming > Xbox Networking now to check NAT type? [Y/n]'
    if ($ans -notmatch '^[nN]') {
        try { Start-Process 'ms-settings:gaming-xboxnetworking' } catch { }
    }
}

function Backup-GameData {
    $src = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState'
    if (-not (Test-Path -LiteralPath $src)) { return $null }
    $dest = Join-Path (Get-DesktopPath) ('Minecraft-Bedrock-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force -ErrorAction Stop
        return $dest
    } catch {
        Warn ('Backup failed: ' + $_.Exception.Message)
        return $null
    }
}

function Invoke-ResetApp {
    $pkg = Get-GamePackage
    if (-not $pkg) { Fail 'Minecraft for Windows is not installed.'; return }

    Head 'Repair Minecraft (reset the app package)'
    Warn 'A reset returns Minecraft to a clean state and CLEARS local worlds and settings.'
    Info 'Worlds are stored in LocalState\games\com.mojang - a Desktop backup is offered.'

    $ans = Read-Host '  Back up worlds and settings to the Desktop first? [Y/n]'
    if ($ans -notmatch '^[nN]') {
        $dest = Backup-GameData
        if ($dest) { Fixed ('Backup saved to ' + $dest) } else { Warn 'Nothing to back up, or the backup failed' }
    }

    $go = Read-Host '  Continue with the reset? [y/N]'
    if ($go -notmatch '^[yY]') { Info 'Cancelled'; return }

    try {
        Reset-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Fixed 'Minecraft app package reset'
        Info 'Start the game from the Store tile; the first launch takes a while.'
    } catch {
        Warn ('Reset-AppxPackage failed: ' + $_.Exception.Message)
        Info 'Manual route: Settings > Apps > Minecraft > Advanced options > Repair, then Reset.'
    }
}

function Invoke-Reinstall {
    Head 'Clean reinstall from the Microsoft Store'
    $pkg = Get-GamePackage
    if ($pkg) {
        Warn ('This removes ' + $pkg.PackageFullName + ' for this user, then opens the Store page.')
        $go = Read-Host '  Continue? [y/N]'
        if ($go -notmatch '^[yY]') { Info 'Cancelled'; return }

        $ans = Read-Host '  Back up worlds and settings to the Desktop first? [Y/n]'
        if ($ans -notmatch '^[nN]') {
            $dest = Backup-GameData
            if ($dest) { Fixed ('Backup saved to ' + $dest) } else { Warn 'Nothing to back up, or the backup failed' }
        }

        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
            Fixed 'Old package removed'
        } catch {
            Warn ('Remove failed: ' + $_.Exception.Message)
            Info 'Close Minecraft, then retry. Otherwise: Settings > Apps > Minecraft > Uninstall.'
        }
    } else {
        Info 'No existing package found - installing fresh.'
    }

    Info 'Opening the official Minecraft for Windows page in the Microsoft Store...'
    try { Start-Process $StoreUrl } catch { Start-Process $WebUrl }
    Info 'Sign in with the account that owns Minecraft, then press Get / Install.'
    Info 'Optional: the Xbox app (Store > Xbox) is the easiest way to sign in first.'
}

function Invoke-InstallPage {
    Head 'Install from the Microsoft Store'
    if (-not (Test-Package 'Microsoft.WindowsStore')) {
        Warn 'The Microsoft Store itself is missing.'
        Info 'Repair it with: Get-AppxPackage Microsoft.WindowsStore | Reset-AppxPackage'
    }
    Info ('Product: Minecraft for Windows  (Store id ' + $StoreId + ')')
    try { Start-Process $StoreUrl } catch { Start-Process $WebUrl }
    Info ('If nothing opened, use: ' + $WebUrl)
    Info 'Sign in with the Microsoft account that owns the game, then press Get / Install.'
    Info 'A genuine Store copy is the only version that can sign in to Xbox Live.'
}

function Invoke-Launch {
    $pkg = Get-GamePackage
    if (-not $pkg) { Fail 'Minecraft for Windows is not installed.'; return }
    $aumid = $pkg.PackageFamilyName + '!App'
    try {
        Start-Process ('shell:AppsFolder\' + $aumid)
        Fixed 'Minecraft launched'
    } catch {
        Warn ('Could not launch: ' + $_.Exception.Message)
        Info 'Start it from the Start menu instead.'
    }
}

function Save-Report {
    $desktop = Get-DesktopPath
    $file = Join-Path $desktop ('Minecraft-Bedrock-Report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Minecraft Bedrock - Setup and Online Play Doctor')
    $lines.Add('Generated : ' + (Get-Date))
    $lines.Add('Computer  : ' + $env:COMPUTERNAME)
    $lines.Add('User      : ' + $env:USERNAME)
    $lines.Add('Admin     : ' + (Test-Admin))
    $lines.Add('')
    foreach ($l in $global:Report) { $lines.Add($l) }
    try {
        Set-Content -LiteralPath $file -Value ($lines.ToArray()) -Encoding UTF8 -ErrorAction Stop
        Fixed ('Report saved to ' + $file)
    } catch {
        Warn ('Could not save the report: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
#  Menu
# ---------------------------------------------------------------------------

function Invoke-Elevate {
    if (Test-Admin) { return }
    if (-not $SelfPath -or -not (Test-Path -LiteralPath $SelfPath)) {
        Warn 'Run this file again with "Run as administrator".'
        return
    }
    $ans = Read-Host '  Relaunch this tool as Administrator now? [Y/n]'
    if ($ans -match '^[nN]') { Info 'Continuing without Administrator rights'; return }
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"' + $SelfPath + '"')) -Verb RunAs | Out-Null
        Write-Host ''
        Write-Host '  An elevated window is opening. This one will close.' -ForegroundColor Green
        Start-Sleep -Seconds 2
        exit
    } catch {
        Warn 'Elevation was cancelled - repairs may fail'
    }
}

function Show-Menu {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '    Minecraft Bedrock  -  Setup and Online Play Doctor' -ForegroundColor Cyan
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '    1   Full health check (system, game, Xbox, network)'
    Write-Host '    2   Install Minecraft from the Microsoft Store'
    Write-Host '    3   Fix online play (services, network, firewall, hosts)'
    Write-Host '    4   Repair Minecraft (reset package, keeps a backup)'
    Write-Host '    5   Launch Minecraft'
    Write-Host '    6   Clean reinstall from the Microsoft Store'
    Write-Host '    7   Save a diagnostic report to the Desktop'
    Write-Host '    0   Exit'
    Write-Host ''
    if (Test-Admin) {
        Write-Host '    Status: Administrator' -ForegroundColor Green
    } else {
        Write-Host '    Status: standard user (repairs will ask to elevate)' -ForegroundColor Yellow
    }
    Write-Host '    Genuine Store copies only - nothing here bypasses licensing.' -ForegroundColor DarkGray
}

Show-Banner
if (-not (Test-Admin)) { Invoke-Elevate }

$running = $true
while ($running) {
    Show-Menu
    $choice = Read-Host '  Choose an option'
    $sel = ''
    if ($choice) { $sel = $choice.Trim() }

    if ($sel -eq '1') { Invoke-FullCheck | Out-Null; Pause-Script }
    elseif ($sel -eq '2') { Invoke-InstallPage; Pause-Script }
    elseif ($sel -eq '3') { Invoke-OnlineFix; Pause-Script }
    elseif ($sel -eq '4') { Invoke-ResetApp; Pause-Script }
    elseif ($sel -eq '5') { Invoke-Launch; Pause-Script }
    elseif ($sel -eq '6') { Invoke-Reinstall; Pause-Script }
    elseif ($sel -eq '7') { Invoke-FullCheck | Out-Null; Save-Report; Pause-Script }
    elseif ($sel -eq '0') { $running = $false }
    elseif ($sel -eq '') { }
    else { Write-Host '  Unknown option - type a number from the list.' -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '  Done. Thanks for playing Minecraft the legitimate way.' -ForegroundColor Cyan
Write-Host ''
