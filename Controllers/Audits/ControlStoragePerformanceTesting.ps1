function controlStoragePerformanceTesting{
    $isEncrypted = "Unknown"
    $fdeType = "Unknown"
    $osName = "Unknown"

    if ($IsWindows) {
        $osName = "Windows"
        Write-Host "[Windows] Testing BitLocker & Storage Performance status..." @Net
        $fdeType = "BitLocker"
        try {
            $osDrive = $env:SystemDrive
            $volume = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftVolumeEncryption" -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$osDrive'" -ErrorAction Stop
            
            if ($volume.ProtectionStatus -eq 1) {
                $isEncrypted = $true
                $fdeMessage = "BitLocker is active (Protection On) on the OS drive ($osDrive)."
            } else {
                $isEncrypted = "Requires Admin"
            }
        }
        catch {
            $bdeStatus = manage-bde -status $env:SystemDrive 2>&1 | Out-String
            if ($bdeStatus -match "Protection On") {
                $isEncrypted = $true
                $fdeMessage = "BitLocker is active on the OS drive ($env:SystemDrive)."
            } elseif ($bdeStatus -match "Protection Off") {
                $isEncrypted = $false
                $fdeMessage = "BitLocker is NOT active on OS drives ($env:SystemDrive)."
            } else {
                $isEncrypted = "Requires Admin"
                $fdeMessage = "Status BitLocker: Need Administrator access."
            }
        }
    }
    elseif ($IsLinux) {
        $osName = "Linux"
        Write-Host "[Linux] Testing LUKS & Performance Storage status..." @Net
        $fdeType = "LUKS"
        $lsblkOutput = lsblk -f 2>&1 | Out-String
        if ($lsblkOutput -match "crypto_LUKS") {
            $isEncrypted = $true
        } else {
            $crypttab = if (Test-Path "/etc/crypttab") { Get-Content "/etc/crypttab" -ErrorAction SilentlyContinue | Out-String } else { "" }
            if ($crypttab -match "\S+\s+\S+") { $isEncrypted = $true } else { $isEncrypted = $false }
        }
    }
    elseif ($IsMacOS) {
        $osName = "macOS"
        Write-Host "[macOS] Testing FileVault & Storage Performance status..." @Net
        $fdeType = "FileVault"
        if (Test-Path "/usr/bin/fdesetup") {
            $fdeStatus = /usr/bin/fdesetup status 2>&1 | Out-String
            if ($fdeStatus -match "FileVault is On") { $isEncrypted = $true } 
            elseif ($fdeStatus -match "FileVault is Off") { $isEncrypted = $false } 
            else { $isEncrypted = "Unknown" }
        } else {
            $isEncrypted = "Unknown"
        }
    }

    $writeSpeed = 0
    $readSpeed = 0
    $writeIops = 0
    $readIops = 0
    $perfStatus = "WARNING"
    $storageTested = "Unknown"
    $forensicStatus = "Unknown"
    $fs = $null
    
    try {
        $testFileSizeMB = 100
        $bufferSize = $testFileSizeMB * 1048576
        $tempDir = [System.IO.Path]::GetTempPath()
        $testFile = Join-Path $tempDir "rasamala_storage_test_$([guid]::NewGuid()).tmp"
        
        $dummyData = New-Object byte[] $bufferSize
        (New-Object Random).NextBytes($dummyData)

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

        if ($readSpeed -gt 5000) { 
            $storageTested = "NVMe EXTREME"
            $forensicStatus = "Inferred SSD (Uncarvable/TRIM)"
        }
        elseif ($readSpeed -gt 2500) { 
            $storageTested = "NVMe HIGH-END"
            $forensicStatus = "Inferred SSD (Uncarvable/TRIM)"
        }
        elseif ($readSpeed -ge 600) { 
            $storageTested = "NVMe MID-RANGE"
            $forensicStatus = "Inferred SSD (Uncarvable/TRIM)"
        }
        elseif ($readSpeed -ge 150) { 
            $storageTested = "SATA SSD / ENTRY"
            $forensicStatus = "Inferred SSD (Uncarvable/TRIM)"
        }
        else { 
            $storageTested = "HDD / VIRTUALIZED"
            $forensicStatus = "Inferred HDD (Carvable)"
        }

        if ($writeSpeed -ge 50 -and $readSpeed -ge 50) { $perfStatus = "OK" }
    }
    catch {
        $perfStatus = "ERROR"
        $storageTested = "Failed to test"
    }
    finally {
        if ($null -ne $fs) {
            $fs.Dispose()
        }
        if (Test-Path $testFile -ErrorAction SilentlyContinue) {
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }
    }

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