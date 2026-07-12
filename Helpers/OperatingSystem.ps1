function helperOperatingSystem {

    Write-Host "`n[+] Mengumpulkan Informasi Sistem Operasi..." -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Gray

    # Deteksi Windows yang aman untuk semua versi PowerShell
    $ApakahWindows = $IsWindows -or ($env:OS -like "*Windows*")

    if ($ApakahWindows) {
        $os = Get-CimInstance Win32_OperatingSystem
        $OSName    = $os.Caption
        $OSVersion = $os.Version
        $OSBuild   = $os.BuildNumber
        $OSArch    = $os.OSArchitecture
        $CurrentUser = $env:USERNAME
    } 
    elseif ($IsLinux) { # <- Sudah diperbaiki menjadi elseif
        $OSName    = (Get-Content /etc/os-release | Select-String "PRETTY_NAME=").ToString().Split('"')[1]
        $OSVersion = (uname -r)
        $OSBuild   = "N/A (Linux Kernel)"
        $OSArch    = (uname -m)
        $CurrentUser = $env:USER
    } 
    elseif ($IsMacOS) { # <- Sudah diperbaiki menjadi elseif
        $OSName    = "macOS " + (sw_vers -productVersion)
        $OSVersion = (sw_vers -buildVersion)
        $OSBuild   = (uname -v)
        $OSArch    = (uname -m)
        $CurrentUser = $env:USER
    }

    # KELUARAN OUTPUT YANG SERAGAM
    Write-Host " Nama OS        : " -NoNewline; Write-Host $OSName -ForegroundColor White
    Write-Host " Versi OS       : " -NoNewline; Write-Host $OSVersion -ForegroundColor White
    Write-Host " Build/Kernel   : " -NoNewline; Write-Host $OSBuild -ForegroundColor White
    Write-Host " Arsitektur     : " -NoNewline; Write-Host $OSArch -ForegroundColor White
    Write-Host " Pengguna Aktif : " -NoNewline; Write-Host $CurrentUser -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Gray

}

