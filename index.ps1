param(
    [switch]$OperatingSystem,
    [switch]$CheckingUpdateSystem,
    [switch]$CheckingDiskEncryption,
    [switch]$CheckingFirewall,
    [switch]$CheckingNetworkPorts
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Helpers\OperatingSystem.ps1

function showBanner {
    helperBanner
}

showBanner

if ($OperatingSystem){
	helperOperatingSystem
}

if ($CheckingUpdateSystem){
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


if ($CheckingDiskEncryption){
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

if ($CheckingFirewall){
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


if ($CheckingNetworkPorts){
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






