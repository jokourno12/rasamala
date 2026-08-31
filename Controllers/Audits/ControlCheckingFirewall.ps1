. $PSScriptRoot\..\..\Config\Windows.ps1

function controlCheckingFirewall{
    # 1. WINDOWS (Windows Defender Firewall)
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa Windows Defender Firewall..." @Net
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
        Write-Host "[Linux] Memeriksa status UFW/Firewalld..." @Net
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
        Write-Host "[macOS] Memeriksa Application Layer Firewall (ALF)..." @Net
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