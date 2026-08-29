. $PSScriptRoot\..\..\Middleware\MiddlewareBrowserIsolationLock.ps1
. $PSScriptRoot\..\..\Config\Windows.ps1

function controlBrowserIsolation{
    $enginePath = Join-Path $PSScriptRoot "engine\EngineBrowserIsolation.js"
    $lockFile   = Join-Path ([System.IO.Path]::GetTempPath()) "rasamala_session.lock"

    if (-not (Test-Path $enginePath)) {
        Write-Error "[!] Berkas engine tidak ditemukan di: $enginePath"
        return
    }

    # Bersihkan sisa lock file dari sesi yang mungkin crash sebelumnya
    if (Test-Path $lockFile) { Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue }

    $denoArgs = @(
        "run",
        "--allow-env",
        "--allow-read",
        "--allow-write",
        "--allow-run",
        "`"$enginePath`"",
        "`"$TargetUrl`"",
        "`"$lockFile`""
    )

    try {
        # 1. Jalankan Deno secara asinkron murni
        Start-Process -FilePath "deno" -ArgumentList $denoArgs -NoNewWindow
        
        # 2. Tunggu maksimal 5 detik sampai Deno berhasil membuat Lock File
        $waitCount = 0
        while (-not (Test-Path $lockFile) -and $waitCount -lt 5) {
            Start-Sleep -Seconds 1
            $waitCount++
        }
        
        # 3. Panggil sistem pengaman sesi (In-App Lock)
        middlewareBrowserIsolationLock
        
        # 4. Tahan prompt PowerShell selama Lock File masih eksis
        while (Test-Path $lockFile) {
            Start-Sleep -Seconds 2
        }
    }
    catch {
        Write-Warning "Terjadi kegagalan rute Deno: $_"
    }
}