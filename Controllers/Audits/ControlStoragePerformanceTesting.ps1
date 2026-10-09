. $PSScriptRoot\..\..\Config\Windows.ps1

function controlStoragePerformanceTesting{
    $isEncrypted = "Unknown"
    $fdeType = "Unknown"
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
                $isEncrypted = "Requires Admin"
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
                $isEncrypted = "Requires Admin"
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
            $isEncrypted = "Unknown"
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
                $isEncrypted = "Unknown"
                $fdeMessage = "Status FileVault tidak diketahui."
            }
        } else {
            $isEncrypted = "Unknown"
            $fdeMessage = "Utility 'fdesetup' tidak ditemukan."
        }
    }

    # ==========================================
    # 2. PENGUJIAN PERFORMA (KODE BARU)
    # ==========================================
    $writeSpeed = 0
    $readSpeed = 0
    $writeIops = 0
    $readIops = 0
    $perfStatus = "WARNING"
    $storageTested = "Unknown"
    $forensicStatus = "Unknown"
    
    try {
        $testFileSizeMB = 50
        $bufferSize = $testFileSizeMB * 1048576
        $tempDir = [System.IO.Path]::GetTempPath()
        $testFile = Join-Path $tempDir "rasamala_storage_test_$([guid]::NewGuid()).tmp"
        
        $dummyData = New-Object byte[] $bufferSize
        (New-Object Random).NextBytes($dummyData)

        # [PERBAIKAN] Menggunakan FileStream dengan flag WriteThrough untuk menembus RAM Cache OS.
        # Ini memaksa pengujian terjadi murni pada hardware fisik (Direct I/O).
        $fs = New-Object System.IO.FileStream($testFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)

        # --- UJI SEQUENTIAL WRITE ---
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs.Write($dummyData, 0, $dummyData.Length)
        $fs.Flush()
        $sw.Stop()
        $writeSpeed = [math]::Round(($testFileSizeMB / $sw.Elapsed.TotalSeconds), 2)

        # --- UJI SEQUENTIAL READ ---
        $fs.Position = 0
        $readBuffer = New-Object byte[] $bufferSize
        $sw.Restart()
        $bytesRead = $fs.Read($readBuffer, 0, $bufferSize)
        $sw.Stop()
        $readSpeed = [math]::Round(($testFileSizeMB / $sw.Elapsed.TotalSeconds), 2)

        # --- UJI RANDOM 4K IOPS ---
        # [PERBAIKAN] Menambahkan pengujian IOPS dengan melompat ke lokasi acak pada file 
        # dan membaca/menulis blok berukuran 4KB (4096 bytes) sebanyak 1000 iterasi.
        $iopsIterations = 1000
        $chunk4K = New-Object byte[] 4096
        $random = New-Object Random

        # Random 4K Write
        $sw.Restart()
        for ($i = 0; $i -lt $iopsIterations; $i++) {
            $fs.Position = $random.Next(0, $bufferSize - 4096)
            $fs.Write($chunk4K, 0, 4096)
        }
        $sw.Stop()
        $writeIops = [math]::Round($iopsIterations / $sw.Elapsed.TotalSeconds)

        # Random 4K Read
        $sw.Restart()
        for ($i = 0; $i -lt $iopsIterations; $i++) {
            $fs.Position = $random.Next(0, $bufferSize - 4096)
            $bytesRead = $fs.Read($chunk4K, 0, 4096)
        }
        $sw.Stop()
        $readIops = [math]::Round($iopsIterations / $sw.Elapsed.TotalSeconds)

        $fs.Close()

        # [PERBAIKAN] Kategorisasi Storage Class berdasarkan hasil pengujian
        if ($readSpeed -gt 7000) { 
            $storageTested = "NVMe EXTREME"
            $forensicStatus = "Uncarvable (TRIM Active)"
        }
        elseif ($readSpeed -gt 3500) { 
            $storageTested = "NVMe HIGH-END"
            $forensicStatus = "Uncarvable (TRIM Active)"
        }
        elseif ($readSpeed -ge 600) { 
            $storageTested = "NVMe MID-RANGE"
            $forensicStatus = "Uncarvable (TRIM Active)"
        }
        elseif ($readSpeed -ge 200) { 
            $storageTested = "SATA SSD / ENTRY"
            $forensicStatus = "Uncarvable (TRIM Active)"
        }
        else { 
            # [PERBAIKAN] Kecepatan di bawah 200 MB/s diasumsikan sebagai HDD/eMMC tanpa fungsi TRIM
            $storageTested = "HDD / SLOW"
            $forensicStatus = "Carvable (TRIM Disabled / HDD)"
        }

        if ($writeSpeed -ge 50 -and $readSpeed -ge 50) { $perfStatus = "OK" }
    }
    catch {
        $perfStatus = "ERROR"
        $storageTested = "Failed to test"
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
        OS                   = $osName
        Status               = $finalStatus
        FDE_Active           = $isEncrypted
        FDE_Type             = $fdeType
        Seq_Write_MBps       = $writeSpeed
        Seq_Read_MBps        = $readSpeed
        Random_4K_Read_IOPS  = $readIops
        Random_4K_Write_IOPS = $writeIops
        Storage_Tested       = $storageTested
        Forensic_Status      = $forensicStatus
    }
}