. $PSScriptRoot\..\Controllers\Remediations\ControlF5Reset.ps1

function middlewareF5Reset{
    # 1. Peringatan Dampak dan Konsekuensi Sistem
    Write-Host "========================================================" -ForegroundColor Red
    Write-Host "           PERINGATAN KRITIS: F5 EPSEC RESET            " -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Red
    Write-Warning "Anda akan melakukan reset total pada layanan F5 Client."
    Write-Host "Akibat yang akan terjadi pada sistem:" -ForegroundColor Yellow
    Write-Host "  * Seluruh proses background terkait F5 akan dihentikan paksa (-Force)."
    Write-Host "  * Layanan inti (seperti f5epsv / Edge Client) akan direstart ulang."
    Write-Host "  * Cache DNS sistem operasi akan dibersihkan (*Flush DNS*)."
    Write-Host "  * Koneksi jaringan aktif (*active session*) akan terputus."
    Write-Host "--------------------------------------------------------" -ForegroundColor Red

    # 2. Permintaan Konfirmasi Interaktif & Validasi Password
    $confirm = Read-Host "Apakah Anda yakin akan melakukan F5 reset? Ketikkan password 'reset' untuk melanjutkan"

    # 3. Validasi Kata Kunci
    if ($confirm -eq "reset") {
        Write-Host "[Middleware] Konfirmasi diterima. Melanjutkan eksekusi..." -ForegroundColor Green
        
        # Panggil Controller utama
        controlF5Reset
    } else {
        Write-Host "[Middleware] Proses dibatalkan. Kata sandi salah atau tindakan dibatalkan oleh pengguna." -ForegroundColor Red
    }
}