function controlCheckingOutboundConnection{
    Write-Host "`n[*] Memulai Audit Outbound Connections..." -ForegroundColor Yellow
        $outboundConns = @()

        # ==========================================
        # 1. WINDOWS: Menggunakan Get-NetTCPConnection
        # ==========================================
        if ($IsWindows) {
            Write-Host "[+] Menjalankan modul OS: WINDOWS" -ForegroundColor Cyan
            
            # Ambil semua koneksi TCP yang ESTABLISHED
            $tcpConns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
            
            foreach ($conn in $tcpConns) {
                # Filter: Abaikan koneksi ke diri sendiri (Loopback: 127.0.0.1 atau ::1)
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
        }
        
        # ==========================================
        # 2. LINUX: Menggunakan utilitas 'ss'
        # ==========================================
        elseif ($IsLinux) {
            Write-Host "[+] Menjalankan modul OS: LINUX" -ForegroundColor Cyan
            
            # ss -ntp (Numeric, TCP, Processes)
            $ssOutput = ss -ntp state established 2>$null
            
            foreach ($line in $ssOutput) {
                # Regex menangkap IP Lokal, IP Remote, dan Data Proses
                if ($line -match 'ESTAB\s+\d+\s+\d+\s+(\S+)\s+(\S+)') {
                    $local  = $matches[1]
                    $remote = $matches[2]
                    
                    # Filter Loopback
                    if ($remote -notmatch '^127\.' -and $remote -notmatch '^\[?::1\]?:') {
                        $procName = "Unknown"
                        $pid      = "N/A"
                        
                        # Parsing nama proses dari string: users:(("bash",pid=1234,fd=3))
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
        }

        # ==========================================
        # 3. MACOS: Menggunakan utilitas 'lsof'
        # ==========================================
        elseif ($IsMacOS) {
            Write-Host "[+] Menjalankan modul OS: MACOS" -ForegroundColor Cyan
            
            # lsof -iTCP -sTCP:ESTABLISHED
            $lsofOutput = lsof -iTCP -sTCP:ESTABLISHED -n -P 2>$null
            
            foreach ($line in $lsofOutput) {
                # Regex menangkap Nama, PID, Local->Remote
                if ($line -match '^(\S+)\s+(\d+).*?TCP\s+(\S+)->(\S+)\s+\(ESTABLISHED\)') {
                    $procName = $matches[1]
                    $pid      = $matches[2]
                    $local    = $matches[3]
                    $remote   = $matches[4]
                    
                    # Filter Loopback
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
        }

        # ==========================================
        # 4. KONSOLIDASI HASIL AUDIT
        # ==========================================
        # Catatan: Memiliki Outbound aktif itu hal lumrah (seperti browser/updater), 
        # jadi status diset ke WARNING jika ada, untuk direview analis SOC.
        
        $osPlatformName = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" }
        
        $auditResults['OutboundConnection'] = [PSCustomObject]@{
            OSPlatform       = $osPlatformName
            Status           = if ($outboundConns.Count -gt 0) { "WARNING" } else { "PASS" }
            TotalConnections = $outboundConns.Count
            Details          = @($outboundConns)
        }
        
        # Cetak langsung ke layar
        $auditResults['OutboundConnection'] | ConvertTo-Json -Depth 4
}