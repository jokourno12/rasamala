. $PSScriptRoot\..\..\Config\Windows.ps1

function controlStoragePerformanceTesting{
    $isEncrypted = $null
    $fdeType = "Unknown"
    $fdeMessage = ""
    $osName = "Unknown"

    # ==========================================
    # 1. PEMERIKSAAN ENKRIPSI DISK (KODE LAMA)
    # ==========================================
    if ($IsWindows) {
        $osName = "Windows"
        Write-Host "[Windows] Memeriksa status BitLocker & Performa Storage..." @Net
        $fdeType = "BitLocker"
        try {
            $osDrive = $env:SystemDrive
            $volume = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$osDrive'" -ErrorAction Stop
            
            if ($volume.ProtectionStatus -eq 1) {
                $isEncrypted = $true
                $fdeMessage = "BitLocker aktif (Protection On) pada drive OS ($osDrive)."
            } else {
                $isEncrypted = $false
                $fdeMessage = "BitLocker TIDAK aktif pada drive OS ($osDrive)."
            }
        }
        catch {
            $bdeStatus = manage-bde -status $env:SystemDrive 2>&1 | Out-String
            if ($bdeStatus -match "Protection On") {
                $isEncrypted = $true
                $fdeMessage = "BitLocker aktif pada drive OS ($env:SystemDrive)."
            } elseif ($bdeStatus -match "Protection Off") {
                $isEncrypted = $false
                $fdeMessage = "BitLocker TIDAK aktif pada drive OS ($env:SystemDrive)."
            } else {
                $isEncrypted = $null
                $fdeMessage = "Status BitLocker: Butuh akses Administrator."
            }
        }
    }
    elseif ($IsLinux) {
        $osName = "Linux"
        Write-Host "[Linux] Memeriksa status LUKS & Performa Storage..." @Net
        $fdeType = "LUKS"
        if (Get-Command lsblk -ErrorAction SilentlyContinue) {
            $lsblkOutput = lsblk -f 2>&1 | Out-String
            if ($lsblkOutput -match "crypto_LUKS") {
                $isEncrypted = $true
                $fdeMessage = "Partisi terenkripsi LUKS terdeteksi."
            } else {
                $isEncrypted = $false
                $fdeMessage = "LUKS tidak terdeteksi."
            }
        } else {
            $fdeMessage = "Utility 'lsblk' tidak ditemukan."
        }
    }
    elseif ($IsMacOS) {
        $osName = "macOS"
        Write-Host "[macOS] Memeriksa status FileVault & Performa Storage..." @Net
        $fdeType = "FileVault"
        if (Get-Command fdesetup -ErrorAction SilentlyContinue) {
            $fdeStatus = fdesetup status 2>&1 | Out-String
            if ($fdeStatus -match "FileVault is On") {
                $isEncrypted = $true
                $fdeMessage = "FileVault aktif."
            } elseif ($fdeStatus -match "FileVault is Off") {
                $isEncrypted = $false
                $fdeMessage = "FileVault TIDAK aktif."
            } else {
                $fdeMessage = "Status FileVault tidak diketahui."
            }
        } else {
            $fdeMessage = "Utility 'fdesetup' tidak ditemukan."
        }
    }

    # ==========================================
    # 2. PENGUJIAN PERFORMA (KODE BARU)
    # ==========================================
    $writeSpeed = 0
    $readSpeed = 0
    $perfMessage = ""
    $perfStatus = "WARNING"
    
    try {
        $testFileSizeMB = 50
        $bufferSize = $testFileSizeMB * 1048576
        $tempDir = [System.IO.Path]::GetTempPath()
        $testFile = Join-Path $tempDir "rasamala_storage_test_$([guid]::NewGuid()).tmp"
        
        $dummyData = New-Object byte[] $bufferSize
        (New-Object Random).NextBytes($dummyData)

        # Uji Write
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($testFile, $dummyData)
        $sw.Stop()
        $writeSpeed = [math]::Round(($testFileSizeMB / $sw.Elapsed.TotalSeconds), 2)

        # Uji Read
        $sw.Restart()
        $null = [System.IO.File]::ReadAllBytes($testFile)
        $sw.Stop()
        $readSpeed = [math]::Round(($testFileSizeMB / $sw.Elapsed.TotalSeconds), 2)
        
        # Evaluasi performa minimal 50 MB/s
        if ($writeSpeed -ge 50 -and $readSpeed -ge 50) { $perfStatus = "OK" }
        $perfMessage = "Performa: Tulis $writeSpeed MB/s, Baca $readSpeed MB/s."
    }
    catch {
        $perfStatus = "ERROR"
        $perfMessage = "Uji performa gagal: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $testFile -ErrorAction SilentlyContinue) {
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }
    }

    # ==========================================
    # 3. GABUNGKAN HASIL OUTPUT
    # ==========================================
    # Status keseluruhan: Jika enkripsi mati ($false) ATAU performa lambat, maka statusnya WARNING
    $finalStatus = $perfStatus
    if ($isEncrypted -eq $false) { $finalStatus = "WARNING" }

    return [PSCustomObject]@{
        OS             = $osName
        Status         = $finalStatus
        FDE_Active     = $isEncrypted
        FDE_Type       = $fdeType
        WriteSpeedMBps = $writeSpeed
        ReadSpeedMBps  = $readSpeed
        Message        = "$fdeMessage | $perfMessage"
    }
}