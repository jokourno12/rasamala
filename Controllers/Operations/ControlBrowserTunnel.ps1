. $PSScriptRoot\..\..\Config\Windows.ps1

function controlBrowserTunnel{
    $urlToOpen = $TargetUrl
    $isInternalUrl = ($urlToOpen -match "^about:") -or ($urlToOpen -match "^chrome:") -or ($urlToOpen -match "^edge:")
    
    $resolvedIp = $null
    $targetHost = $null

    # 1. Intervensi DNS hanya jika target BUKAN URL internal
    if (-not $isInternalUrl) {
        if ($urlToOpen -notmatch "^https?://") {
            $urlToOpen = "https://" + $urlToOpen
        }
        
        try {
            $targetHost = ([uri]$urlToOpen).Host
            Write-Host "[*] Menyiapkan Direct Routing: Inisialisasi IP untuk $targetHost via DoH API..." @Cha
            
            $dohUrl = "https://dns.google/resolve?name=$targetHost"
            $response = Invoke-RestMethod -Uri $dohUrl -Method Get -ErrorAction Stop
            
            $aRecord = $response.Answer | Where-Object { $_.type -eq 1 } | Select-Object -First 1
            
            if ($aRecord) {
                $resolvedIp = $aRecord.data
                Write-Host "[+] Direct Tunneling Berhasil! Target IP: $resolvedIp" @App
            } else {
                Write-Host "[-] Alamat IP tidak ditemukan melalui resolver sekunder." @Pen
            }
        } catch {
            Write-Host "[-] Kendala pada pemrosesan URL atau koneksi resolver." @Pen
        }
    }

    # 2. Deteksi lokasi executable Chrome / Edge secara dinamis
    $browserPath = $null
    $possiblePaths = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $browserPath = $path
            break
        }
    }

    if (-not $browserPath) {
        Write-Host "[!] Browser (Chrome/Edge) tidak ditemukan di lokasi standar." @Pen
    } else {
        $tempProfile = Join-Path $env:TEMP "Rasamala_Direct_$(Get-Random)"

        $browserArgs = @(
            "--user-data-dir=$tempProfile",
            "--no-proxy-server",                  
            "--no-first-run",
            $urlToOpen
        )

        # 3. Menerapkan pemetaan rute langsung jika IP didapat
        if ($resolvedIp -and $targetHost) {
            $browserArgs += "--host-resolver-rules=`"MAP $targetHost $resolvedIp`""
        }

        Write-Host "[+] Meluncurkan Direct Browser via: $browserPath" @Net
        
        $process = Start-Process -FilePath $browserPath -ArgumentList $browserArgs -PassThru -Wait

        if (Test-Path $tempProfile) {
            Remove-Item -Path $tempProfile -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[Rasamala] Profile direktori sementara berhasil dibersihkan." @App
        }
    }
}