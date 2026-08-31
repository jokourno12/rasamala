. $PSScriptRoot\..\..\Config\Windows.ps1

function controlCheckingDiskEncryption{
    # 1. WINDOWS (BitLocker)
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa status BitLocker..." @Net
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
        Write-Host "[Linux] Memeriksa status LUKS Encryption..." @Net
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
        Write-Host "[macOS] Memeriksa status FileVault..." @Net
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