. $PSScriptRoot\..\..\Config\Windows.ps1

function controlCheckingNetworkConnection{
Write-Host "`n[*] Memulai Audit Network & Sockets (Inbound & Outbound)..." -ForegroundColor Cyan

# Inisialisasi variabel penampung
$inboundPorts = @()
$outboundConns = @()
$osPlatform = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" }

# ==========================================
# 1. WINDOWS: Menggunakan Get-NetTCPConnection
# ==========================================
if ($IsWindows) {
    Write-Host "[+] Menjalankan modul Network Audit OS: WINDOWS" -ForegroundColor Green
    
    try {
        # --- A. Inbound / Listening Ports ---
        $listenConns = Get-NetTCPConnection -State Listen -ErrorAction Stop
        $inboundPorts = $listenConns.LocalPort | Select-Object -Unique | Sort-Object

        # --- B. Outbound / Established Connections ---
        $tcpConns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
        foreach ($conn in $tcpConns) {
            if ($conn.RemoteAddress -notmatch '^127\.' -and $conn.RemoteAddress -ne '::1') {
                $procName = "Unknown"
                if ($conn.OwningProcess) {
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    if ($proc) { $procName = $proc.Name }
                }
                
                $outboundConns += [PSCustomObject]@{
                    ProcessName   = $procName
                    PID           = $conn.OwningProcess
                    LocalAddress  = "$($conn.LocalAddress):$($conn.LocalPort)"
                    RemoteAddress = "$($conn.RemoteAddress):$($conn.RemotePort)"
                    State         = $conn.State
                }
            }
        }
    } catch {
        Write-Warning "Gagal membaca koneksi Windows. Pastikan dijalankan sebagai Administrator."
    }
}

# ==========================================
# 2. LINUX: Menggunakan utilitas 'ss'
# ==========================================
elseif ($IsLinux) {
    Write-Host "[+] Menjalankan modul Network Audit OS: LINUX" -ForegroundColor Green
    
    if (Get-Command ss -ErrorAction SilentlyContinue) {
        # --- A. Inbound / Listening Ports ---
        $linesListen = ss -tln 2>/dev/null | Select-String "LISTEN"
        foreach ($line in $linesListen) {
            if ($line -match ":(\d+)\s+") {
                $inboundPorts += [int]$Matches[1]
            }
        }

        # --- B. Outbound / Established Connections ---
        $ssOutput = ss -ntp state established 2>/dev/null
        foreach ($line in $ssOutput) {
            if ($line -match 'ESTAB\s+\d+\s+\d+\s+(\S+)\s+(\S+)') {
                $local  = $matches[1]
                $remote = $matches[2]
                
                if ($remote -notmatch '^127\.' -and $remote -notmatch '^\[?::1\]?:') {
                    $procName = "Unknown"
                    $pid      = "N/A"
                    
                    if ($line -match 'users:\(\("([^"]+)",pid=(\d+)') {
                        $procName = $matches[1]
                        $pid      = $matches[2]
                    }
                    
                    $outboundConns += [PSCustomObject]@{
                        ProcessName   = $procName
                        PID           = $pid
                        LocalAddress  = $local
                        RemoteAddress = $remote
                        State         = "Established"
                    }
                }
            }
        }
    } else {
        Write-Warning "Utilitas 'ss' tidak ditemukan di sistem Linux ini."
    }
}

# ==========================================
# 3. MACOS: Menggunakan utilitas 'lsof'
# ==========================================
elseif ($IsMacOS) {
    Write-Host "[+] Menjalankan modul Network Audit OS: MACOS" -ForegroundColor Green
    
    if (Get-Command lsof -ErrorAction SilentlyContinue) {
        # --- A. Inbound / Listening Ports ---
        $linesListen = lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
        foreach ($line in $linesListen) {
            if ($line -match ":(\d+)\s+\(LISTEN") {
                $inboundPorts += [int]$Matches[1]
            }
        }

        # --- B. Outbound / Established Connections ---
        $lsofOutput = lsof -iTCP -sTCP:ESTABLISHED -n -P 2>/dev/null
        foreach ($line in $lsofOutput) {
            if ($line -match '^(\S+)\s+(\d+).*?TCP\s+(\S+)->(\S+)\s+\(ESTABLISHED\)') {
                $procName = $matches[1]
                $pid      = $matches[2]
                $local    = $matches[3]
                $remote   = $matches[4]
                
                if ($remote -notmatch '^127\.' -and $remote -notmatch '^\[?::1\]?:') {
                    $outboundConns += [PSCustomObject]@{
                        ProcessName   = $procName
                        PID           = $pid
                        LocalAddress  = $local
                        RemoteAddress = $remote
                        State         = "Established"
                    }
                }
            }
        }
    } else {
        Write-Warning "Utilitas 'lsof' tidak ditemukan di sistem macOS ini."
    }
}

# ==========================================
# 4. KONSOLIDASI & FORMAT OUTPUT
# ==========================================
$inboundPorts = $inboundPorts | Select-Object -Unique | Sort-Object | Where-Object { $_ -ne $null }
$portList = if ($inboundPorts) { $inboundPorts -join ", " } else { "None" }

$auditStatus = if ($outboundConns.Count -gt 0) { "WARNING" } else { "PASS" }

$networkAuditResult = [PSCustomObject]@{
    OSPlatform               = $osPlatform
    Status                   = $auditStatus
    ListeningPortsCount      = if ($inboundPorts) { $inboundPorts.Count } else { 0 }
    ListeningPorts           = $portList
    OutboundConnectionsCount = $outboundConns.Count
    OutboundDetails          = @($outboundConns)
}

$networkAuditResult | ConvertTo-Json -Depth 4

}