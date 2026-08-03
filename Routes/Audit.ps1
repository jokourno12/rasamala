. $PSScriptRoot\..\Helpers\OperatingSystem.ps1

function routeOperatingSystem{
    helperOperatingSystem
}

function routeCheckingUpdateSystem{
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa Windows Update Agent..." -ForegroundColor Cyan
        try {
            $session = New-Object -ComObject "Microsoft.Update.Session"
            $searcher = $session.CreateUpdateSearcher()
            
            $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0")
            $pendingCount = $searchResult.Updates.Count
            
            # Kumpulkan detail nama update
            $updateDetails = @()
            if ($pendingCount -gt 0) {
                foreach ($update in $searchResult.Updates) {
                    $updateDetails += $update.Title
                }
            }

            return [PSCustomObject]@{
                OS                  = "Windows"
                IsUpToDate          = ($pendingCount -eq 0)
                PendingUpdatesCount = $pendingCount
                Message             = if ($pendingCount -eq 0) { "Sistem fully updated." } else { "Ada $pendingCount update tertunda." }
                # Menggabungkan array menjadi satu string agar rapi saat ditampilkan di tabel
                PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join " | " } else { "N/A" } 
            }
        }
        catch {
            return [PSCustomObject]@{
                OS                  = "Windows"
                IsUpToDate          = $null
                PendingUpdatesCount = -1
                Message             = "Gagal memeriksa update: $($_.Exception.Message)"
                PendingDetails      = "N/A"
            }
        }
    }

    # 2. LINUX
    elseif ($IsLinux) {
        Write-Host "[Linux] Memeriksa Package Manager..." -ForegroundColor Cyan
        $pendingCount = 0
        $pkgManager = "Unknown"
        $updateDetails = @()

        if (Get-Command apt-get -ErrorAction SilentlyContinue) {
            $pkgManager = "apt"
            # apt list --upgradable menampilkan daftar paket yang bisa diupdate
            $output = apt list --upgradable 2>/dev/null | Select-String -Pattern "/"
            if ($output) {
                $pendingCount = $output.Count
                foreach ($line in $output) {
                    # Format apt list biasanya: nama-paket/distro versi [upgradable...]
                    $pkgName = ($line.ToString() -split "/")[0]
                    $updateDetails += $pkgName
                }
            }
        }
        elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
            $pkgManager = "dnf"
            $null = dnf check-update 2>&1
            if ($LASTEXITCODE -eq 100) {
                $updates = (dnf check-update --quiet 2>&1) | Where-Object { $_ -match '\S+' }
                $pendingCount = $updates.Count
                foreach ($line in $updates) {
                    # Mengambil kata pertama (nama paket) dari baris dnf check-update
                    $pkgName = ($line.ToString() -split '\s+')[0]
                    $updateDetails += $pkgName
                }
            }
        }
        else {
            return [PSCustomObject]@{
                OS                  = "Linux"
                IsUpToDate          = $null
                PendingUpdatesCount = -1
                Message             = "Package manager tidak didukung/ditemukan."
                PendingDetails      = "N/A"
            }
        }

        return [PSCustomObject]@{
            OS                  = "Linux ($pkgManager)"
            IsUpToDate          = ($pendingCount -eq 0)
            PendingUpdatesCount = $pendingCount
            Message             = if ($pendingCount -eq 0) { "Sistem fully updated." } else { "Ada $pendingCount paket dapat di-upgrade." }
            PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join ", " } else { "N/A" }
        }
    }

    # 3. macOS
    elseif ($IsMacOS) {
        Write-Host "[macOS] Memeriksa Software Update CLI..." -ForegroundColor Cyan
        $output = softwareupdate -l 2>&1 | Out-String
        $updateDetails = @()

        if ($output -match "No new software available") {
            return [PSCustomObject]@{
                OS                  = "macOS"
                IsUpToDate          = $true
                PendingUpdatesCount = 0
                Message             = "Sistem fully updated."
                PendingDetails      = "N/A"
            }
        }
        else {
            $matches = [regex]::Matches($output, "\*\s+Label:\s*(.*)")
            $pendingCount = $matches.Count
            
            if ($pendingCount -gt 0) {
                foreach ($match in $matches) {
                    $updateDetails += $match.Groups[1].Value.Trim()
                }
            } else {
                # Fallback jika Regex gagal tapi output tidak mengatakan "No new software"
                $pendingCount = 1
                $updateDetails += "Update terdeteksi, format label tidak dikenali."
            }

            return [PSCustomObject]@{
                OS                  = "macOS"
                IsUpToDate          = $false
                PendingUpdatesCount = $pendingCount
                Message             = "Ada $pendingCount update tertunda."
                PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join " | " } else { "N/A" }
            }
        }
    }
}


function routeCheckingDiskEncryption{
    # 1. WINDOWS (BitLocker)
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa status BitLocker..." -ForegroundColor Cyan
        try {
            $osDrive = $env:SystemDrive
            $isEncrypted = $false
            $message = ""

            # Mencoba via WMI/CIM (biasanya butuh Run as Administrator)
            $volume = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$osDrive'" -ErrorAction Stop
            
            # ProtectionStatus: 0 = Off, 1 = On, 2 = Unknown
            if ($volume.ProtectionStatus -eq 1) {
                $isEncrypted = $true
                $message = "BitLocker aktif (Protection On) pada drive OS ($osDrive)."
            } else {
                $isEncrypted = $false
                $message = "BitLocker TIDAK aktif pada drive OS ($osDrive)."
            }
        }
        catch {
            # Fallback menggunakan utility bawaan manage-bde jika WMI gagal
            $bdeStatus = manage-bde -status $env:SystemDrive 2>&1 | Out-String
            if ($bdeStatus -match "Protection On") {
                $isEncrypted = $true
                $message = "BitLocker aktif pada drive OS ($env:SystemDrive)."
            } elseif ($bdeStatus -match "Protection Off") {
                $isEncrypted = $false
                $message = "BitLocker TIDAK aktif pada drive OS ($env:SystemDrive)."
            } else {
                $isEncrypted = $null
                $message = "Butuh akses Administrator."
            }
        }

        return [PSCustomObject]@{
            OS            = "Windows"
            FDE_Active    = $isEncrypted
            FDE_Type      = "BitLocker"
            Message       = $message
        }
    }

    # 2. LINUX (LUKS)
    elseif ($IsLinux) {
        Write-Host "[Linux] Memeriksa status LUKS Encryption..." -ForegroundColor Cyan
        $isEncrypted = $false
        $message = "LUKS tidak terdeteksi."

        if (Get-Command lsblk -ErrorAction SilentlyContinue) {
            # Membaca filesystem block device untuk mencari partisi terenkripsi LUKS
            $lsblkOutput = lsblk -f 2>&1 | Out-String
            if ($lsblkOutput -match "crypto_LUKS") {
                $isEncrypted = $true
                $message = "Partisi terenkripsi LUKS terdeteksi pada sistem."
            }
        } else {
            $isEncrypted = $null
            $message = "Utility 'lsblk' tidak ditemukan, gagal memeriksa FDE."
        }

        return [PSCustomObject]@{
            OS            = "Linux"
            FDE_Active    = $isEncrypted
            FDE_Type      = "LUKS"
            Message       = $message
        }
    }

    # 3. macOS (FileVault)
    elseif ($IsMacOS) {
        Write-Host "[macOS] Memeriksa status FileVault..." -ForegroundColor Cyan
        $isEncrypted = $false
        $message = ""

        if (Get-Command fdesetup -ErrorAction SilentlyContinue) {
            $fdeStatus = fdesetup status 2>&1 | Out-String
            
            if ($fdeStatus -match "FileVault is On") {
                $isEncrypted = $true
                $message = "FileVault aktif."
            } elseif ($fdeStatus -match "FileVault is Off") {
                $isEncrypted = $false
                $message = "FileVault TIDAK aktif."
            } else {
                $isEncrypted = $null
                $message = "Status FileVault tidak diketahui: $fdeStatus"
            }
        } else {
            $isEncrypted = $null
            $message = "Utility 'fdesetup' tidak ditemukan."
        }

        return [PSCustomObject]@{
            OS            = "macOS"
            FDE_Active    = $isEncrypted
            FDE_Type      = "FileVault"
            Message       = $message
        }
    }
}

function routeCheckingFirewall{
    # 1. WINDOWS (Windows Defender Firewall)
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa Windows Defender Firewall..." -ForegroundColor Cyan
        try {
            $profiles = Get-NetFirewallProfile -ErrorAction Stop
            # Mencari profil yang dimatikan (biasanya nilainya bernilai false atau enum 2)
            $disabledProfiles = $profiles | Where-Object { $_.Enabled -eq $false -or $_.Enabled -eq 2 -or $_.Enabled -match "False" }
            
            if ($disabledProfiles.Count -eq 0) {
                $status = $true
                $msg = "Semua profil Firewall (Domain, Private, Public) aktif."
            } else {
                $status = $false
                $names = ($disabledProfiles.Name) -join ", "
                $msg = "Profil Firewall berikut TIDAK aktif: $names."
            }
        }
        catch {
            # Fallback menggunakan netsh jika cmdlet Get-NetFirewallProfile gagal/terblokir
            $netshStatus = netsh advfirewall show allprofiles state 2>&1 | Out-String
            if ($netshStatus -match "State\s+OFF") {
                $status = $false
                $msg = "Satu atau lebih profil Windows Firewall dalam keadaan OFF."
            } elseif ($netshStatus -match "State\s+ON") {
                $status = $true
                $msg = "Windows Firewall aktif (Berdasarkan fallback netsh)."
            } else {
                $status = $null
                $msg = "Status Firewall tidak dapat dipastikan (Access Denied). Membutuhkan eksekusi sebagai Administrator."
            }
        }

        return [PSCustomObject]@{
            OS              = "Windows"
            Firewall_Active = $status
            Firewall_Type   = "Windows Defender Firewall"
            Message         = $msg
        }
    }

    # 2. LINUX (UFW / Firewalld)
    elseif ($IsLinux) {
        Write-Host "[Linux] Memeriksa status UFW/Firewalld..." -ForegroundColor Cyan
        $status = $false
        $fwType = "Unknown"
        $msg = "Layanan Firewall tidak terdeteksi di sistem."

        if (Get-Command ufw -ErrorAction SilentlyContinue) {
            $fwType = "UFW"
            $ufwStatus = ufw status 2>&1 | Out-String
            
            if ($ufwStatus -match "Status: active") {
                $status = $true
                $msg = "UFW (Uncomplicated Firewall) aktif."
            } elseif ($ufwStatus -match "root" -or $ufwStatus -match "Permission denied") {
                $status = $null
                $msg = "Gagal membaca status UFW. Membutuhkan eksekusi sebagai root (sudo)."
            } else {
                $status = $false
                $msg = "UFW terinstal namun statusnya TIDAK aktif (inactive)."
            }
        }
        elseif (Get-Command firewall-cmd -ErrorAction SilentlyContinue) {
            $fwType = "Firewalld"
            $fwStatus = firewall-cmd --state 2>&1 | Out-String
            
            if ($fwStatus -match "running") {
                $status = $true
                $msg = "Firewalld dalam keadaan aktif (running)."
            } elseif ($fwStatus -match "Authorization failed" -or $fwStatus -match "root") {
                $status = $null
                $msg = "Gagal membaca Firewalld. Membutuhkan eksekusi sebagai root."
            } else {
                $status = $false
                $msg = "Firewalld terinstal namun TIDAK aktif."
            }
        }

        return [PSCustomObject]@{
            OS              = "Linux"
            Firewall_Active = $status
            Firewall_Type   = $fwType
            Message         = $msg
        }
    }

    # 3. macOS (Application Layer Firewall)
    elseif ($IsMacOS) {
        Write-Host "[macOS] Memeriksa Application Layer Firewall (ALF)..." -ForegroundColor Cyan
        $fwType = "ALF"
        $alfPath = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        
        if (Test-Path $alfPath) {
            $alfStatus = & $alfPath --getglobalstate 2>&1 | Out-String
            
            if ($alfStatus -match "Firewall is enabled") {
                $status = $true
                $msg = "macOS Application Firewall aktif."
            } else {
                $status = $false
                $msg = "macOS Application Firewall TIDAK aktif."
            }
        } else {
            $status = $null
            $msg = "Utility Firewall macOS tidak ditemukan di path standar."
        }

        return [PSCustomObject]@{
            OS              = "macOS"
            Firewall_Active = $status
            Firewall_Type   = $fwType
            Message         = $msg
        }
    }
}


function routeCheckingNetworkPorts{
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa Listening Ports TCP..." -ForegroundColor Cyan
        try {
            # Menggunakan Get-NetTCPConnection (PowerShell native)
            $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop
            # Ekstrak port, hilangkan duplikat, dan urutkan
            $ports = $connections.LocalPort | Select-Object -Unique | Sort-Object
            $portList = if ($ports) { $ports -join ", " } else { "None" }

            return [PSCustomObject]@{
                OS             = "Windows"
                OpenPortsCount = if ($ports) { $ports.Count } else { 0 }
                ListeningPorts = $portList
                Message        = "Port TCP terbuka dan siap menerima koneksi (LISTEN)."
            }
        }
        catch {
            return [PSCustomObject]@{
                OS             = "Windows"
                OpenPortsCount = -1
                ListeningPorts = "N/A"
                Message        = "Gagal membaca Listening Ports. Pastikan hak akses cukup."
            }
        }
    }
    elseif ($IsLinux) {
        Write-Host "[Linux] Memeriksa Listening Ports TCP (ss)..." -ForegroundColor Cyan
        $ports = @()
        if (Get-Command ss -ErrorAction SilentlyContinue) {
            # Parsing output dari ss (Socket Statistics)
            $lines = ss -tln 2>/dev/null | Select-String "LISTEN"
            foreach ($line in $lines) {
                # Menggunakan regex untuk menangkap angka port setelah tanda titik dua (contoh: 0.0.0.0:22)
                if ($line -match ":(\d+)\s+") {
                    $ports += [int]$Matches[1]
                }
            }
        }
        
        $ports = $ports | Select-Object -Unique | Sort-Object | Where-Object { $_ -ne $null }
        $portList = if ($ports) { $ports -join ", " } else { "None" }

        return [PSCustomObject]@{
            OS             = "Linux"
            OpenPortsCount = if ($ports) { $ports.Count } else { 0 }
            ListeningPorts = $portList
            Message        = "Port TCP terbuka (LISTEN) yang ditemukan via utilitas 'ss'."
        }
    }
    elseif ($IsMacOS) {
        Write-Host "[macOS] Memeriksa Listening Ports TCP (lsof)..." -ForegroundColor Cyan
        $ports = @()
        if (Get-Command lsof -ErrorAction SilentlyContinue) {
            # Menjalankan lsof untuk mencari TCP LISTEN dan mencegah resolusi DNS (-n)
            $lines = lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
            foreach ($line in $lines) {
                if ($line -match ":(\d+)\s+\(LISTEN") {
                    $ports += [int]$Matches[1]
                }
            }
        }
        
        $ports = $ports | Select-Object -Unique | Sort-Object | Where-Object { $_ -ne $null }
        $portList = if ($ports) { $ports -join ", " } else { "None" }

        return [PSCustomObject]@{
            OS             = "macOS"
            OpenPortsCount = if ($ports) { $ports.Count } else { 0 }
            ListeningPorts = $portList
            Message        = "Port TCP terbuka (LISTEN) yang ditemukan via utilitas 'lsof'."
        }
    }
}

$auditResults = [ordered]@{}

function routeCheckingRemoteSession{
    Write-Host "`n[*] Memulai Audit Remote Session..." -ForegroundColor Yellow
    $sessions = @()

    # ==========================================
    # 1. WINDOWS: Menggunakan 'quser.exe'
    # ==========================================
    if ($IsWindows) {
        Write-Host "[+] Menjalankan modul OS: WINDOWS" -ForegroundColor Cyan
        $quserOutput = quser.exe 2>$null
        
        if ($quserOutput -and $quserOutput.Count -gt 1) {
            for ($i = 1; $i -lt $quserOutput.Count; $i++) {
                $line = $quserOutput[$i] -replace '^>', ' '
                
                if ($line -match '^\s*(\S+)\s+([a-zA-Z0-9\-\#]+)?\s+(\d+)\s+([a-zA-Z]+)') {
                    $username    = $matches[1]
                    $sessionName = if ([string]::IsNullOrWhiteSpace($matches[2])) { "Disconnected" } else { $matches[2] }
                    $state       = $matches[4]
                    
                    $isRemote = $sessionName -match "rdp|ssh|winrm"
                    
                    $sessions += [PSCustomObject]@{
                        Username    = $username
                        SessionType = if ($isRemote) { "Remote ($sessionName)" } else { "Local ($sessionName)" }
                        RemoteHost  = if ($isRemote) { "Unknown/RDP" } else { "localhost" }
                        IsRemote    = $isRemote
                        State       = $state
                    }
                }
            }
        }

        # KONSOLIDASI & TAMPILKAN HASIL KHUSUS WINDOWS
        $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq $true })
        $auditResults['RemoteSession'] = [PSCustomObject]@{
            OSPlatform         = "Windows"
            Status             = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }
            TotalSessions      = $sessions.Count
            RemoteSessionCount = $activeRemoteSessions.Count
            Details            = $sessions
        }
        
        # Cetak langsung ke layar
        $auditResults['RemoteSession'] | ConvertTo-Json -Depth 4
    }
    
    # ==========================================
    # 2. LINUX & MACOS: Menggunakan perintah 'who'
    # ==========================================
    elseif ($IsLinux -or $IsMacOS) {
        $osName = if ($IsLinux) { "LINUX" } else { "MACOS" }
        Write-Host "[+] Menjalankan modul OS: $osName" -ForegroundColor Cyan
        
        $whoOutput = who 2>$null
        
        if ($whoOutput) {
            foreach ($line in $whoOutput) {
                if ($line -match "^(\S+)\s+(\S+)\s+(.*?)\s*(?:\((.*?)\))?$") {
                    $username   = $matches[1]
                    $tty        = $matches[2]
                    $remoteHost = $matches[4]
                    
                    $isRemote = -not [string]::IsNullOrWhiteSpace($remoteHost)
                    
                    $sessions += [PSCustomObject]@{
                        Username    = $username
                        SessionType = if ($isRemote) { "Remote ($tty)" } else { "Local ($tty)" }
                        RemoteHost  = if ($isRemote) { $remoteHost } else { "localhost" }
                        IsRemote    = $isRemote
                        State       = "Active"
                    }
                }
            }
        }

        # KONSOLIDASI & TAMPILKAN HASIL KHUSUS LINUX/MACOS
        $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq $true })
        $auditResults['RemoteSession'] = [PSCustomObject]@{
            OSPlatform         = $osName
            Status             = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }
            TotalSessions      = $sessions.Count
            RemoteSessionCount = $activeRemoteSessions.Count
            Details            = $sessions
        }
        
        # Cetak langsung ke layar
        $auditResults['RemoteSession'] | ConvertTo-Json -Depth 4
    }
}


function routeCheckingOutboundConnection{
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