function controlJavaScriptRuntime{
    Write-Host "[Operation] Memeriksa Deno Runtime..." -ForegroundColor Cyan

    # 1. Deteksi karakteristik OS
    $homeDir = if ($IsWindows) { $env:USERPROFILE } else { $HOME }
    $exeName = if ($IsWindows) { "deno.exe" } else { "deno" }
    $pathSep = [System.IO.Path]::PathSeparator

    # Deteksi lokasi executable Deno
    $denoCmd = Get-Command deno -ErrorAction SilentlyContinue
    $denoExe = if ($denoCmd) { $denoCmd.Source } else { Join-Path $homeDir ".deno/bin/$exeName" }

    # 2. Cek & Install dengan Progress Bar kustom
    if (-not (Test-Path $denoExe)) {
        Write-Host "[Operation] Deno tidak ditemukan. Memulai instalasi..." -ForegroundColor Yellow
        
        $installJob = Start-Job -ScriptBlock {
            $ProgressPreference = 'SilentlyContinue'
            irm https://deno.land/install.ps1 | Out-String | iex *>$null
        }

        $elapsed = 0
        while ($installJob.State -eq 'Running') {
            Write-Host -NoNewline "`rInstalasi Deno Berjalan [Mohon tunggu $elapsed detik... ]" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            $elapsed++
        }

        Receive-Job -Job $installJob | Out-Null
        Remove-Job -Job $installJob

        Write-Host "`rInstalasi Deno Selesai  [Berhasil dalam $elapsed detik]        " -ForegroundColor Green
        
        # Daftarkan ke PATH sesi menggunakan pemisah khas OS ( ; di Windows, : di Linux/macOS)
        $denoBinDir = Join-Path $homeDir ".deno/bin"
        $env:PATH = "$denoBinDir$pathSep$env:PATH"
    }

    # Verifikasi akhir keberadaan biner Deno
    if (-not (Test-Path $denoExe)) {
        Write-Host "`n✕ Binary Deno tidak ditemukan." -ForegroundColor Red
        return
    }

    # 3. Eksekusi file Deno.js
    $targetScript = Join-Path $PSScriptRoot "../../Helpers/Deno.js"
    
    if (Test-Path $targetScript) {
        Write-Host "`n[Operation] Mengeksekusi modul JavaScript..." -ForegroundColor Cyan
        
        & $denoExe run --allow-all $targetScript 
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✕ Modul JavaScript berhenti dengan kesalahan (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
        }
    } else {
        Write-Host "[-] Peringatan: File $targetScript tidak ditemukan." -ForegroundColor Yellow
    }
}