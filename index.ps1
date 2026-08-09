[CmdletBinding()]
param(
    [switch]$OperatingSystem,
    [switch]$CheckingUpdateSystem,
    [switch]$CheckingDiskEncryption,
    [switch]$CheckingFirewall,
    [switch]$CheckingNetworkPorts,
    [switch]$CheckingRemoteSession,
    [switch]$CheckingOutboundConnection,
    [switch]$EndpointMetric,
    [switch]$AqlMonitoring,
    [switch]$F5Reset,

    #[ValidateSet(7, 14, 28, 42)]
    #[int]$InitialInterval = 7,
    [ValidateSet(1, 2, 3, 4)]
    [int]$InitialInterval = 1,
    [switch]$TestingMode
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Routes\Audit.ps1
. $PSScriptRoot\Routes\Operation.ps1
. $PSScriptRoot\Routes\Remediation.ps1

function showBanner {
    helperBanner
}

showBanner
# Audit
if ($OperatingSystem){
    routeOperatingSystem
}

if ($CheckingUpdateSystem){
    routeCheckingUpdateSystem
}

if ($CheckingDiskEncryption){
    routeCheckingDiskEncryption
}

if ($CheckingFirewall){
    routeCheckingFirewall
}

if ($CheckingNetworkPorts){
    routeCheckingNetworkPorts
}

if ($CheckingRemoteSession){
    routeCheckingRemoteSession
}

if ($CheckingOutboundConnection){
    routeCheckingOutboundConnection
}

# Operation
if ($EndpointMetric){
    routeEndpointMetric
}

if ($AqlMonitoring){
    # 1. Inisialisasi Matriks Transisi AQL (Skala Uji Coba: 1, 2, 3, 4)
    $aqlMatrix = @{
        1  = @{
            'C' = @{ Next = 1; Mode = 'Emergency' }
            'H' = @{ Next = 2; Mode = 'Reduced' }
            'M' = @{ Next = 2; Mode = 'Reduced' }
            'L' = @{ Next = 2; Mode = 'Reduced' }
        }
        2 = @{
            'C' = @{ Next = 1; Mode = 'Tightened' }
            'H' = @{ Next = 2; Mode = 'Warning' }
            'M' = @{ Next = 3; Mode = 'Reduced' }
            'L' = @{ Next = 3; Mode = 'Reduced' }
        }
        3 = @{
            'C' = @{ Next = 1; Mode = 'Tightened' }
            'H' = @{ Next = 2; Mode = 'Tightened' }
            'M' = @{ Next = 3; Mode = 'Normal' }
            'L' = @{ Next = 4; Mode = 'Reduced' }
        }
        4 = @{
            'C' = @{ Next = 1; Mode = 'Tightened' }
            'H' = @{ Next = 2; Mode = 'Tightened' }
            'M' = @{ Next = 3; Mode = 'Tightened' }
            'L' = @{ Next = 4; Mode = 'Eco' }
        }
    }

    # 2. State Awal & Histori
    $currentInterval = $InitialInterval
    $currentMode     = "Initial / Emergency"
    $loopCount       = 1
    
    # Variabel penampung riwayat terakhir
    $lastInput       = $null
    $lastInterval    = $null
    $lastMode        = $null

    # 3. Main Loop Monitoring (Dashboard View)
    while ($true) {
        # Bersihkan layar di awal setiap siklus agar tampilan selalu baru/bersih
        Clear-Host

        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host "   AQL SECOPS DYNAMIC MONITORING SYSTEM (TESTING MODE)    " -ForegroundColor Yellow
        Write-Host "==========================================================" -ForegroundColor Cyan
        
        $unitLabel = if ($TestingMode) { "Detik" } else { "Menit" }

        if ($TestingMode) {
            Write-Host " Mode Eksekusi : TESTING MODE (1 Nilai Interval = 1 Detik)" -ForegroundColor Red
        } else {
            Write-Host " Mode Eksekusi : PRODUKSI (1 Nilai Interval = 1 Menit)" -ForegroundColor Green
        }
        Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

        # Jika bukan siklus pertama, tampilkan Ringkasan Histori Terakhir
        if ($loopCount -gt 1) {
            Write-Host " [HISTORI SIKLUS #$($loopCount - 1)]" -ForegroundColor DarkGray
            Write-Host "  * Input Analis  : $lastInput" -ForegroundColor Yellow
            Write-Host "  * Transisi      : $lastInterval $unitLabel ($lastMode) ---> $currentInterval $unitLabel ($currentMode)" -ForegroundColor Gray
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
        }

        # Tampilkan Status Aktif Siklus Saat Ini
        Write-Host " [STATUS MONITORING AKTIF - SIKLUS #$loopCount]" -ForegroundColor Green
        Write-Host "  * Interval Saat Ini : $currentInterval $unitLabel" -ForegroundColor White
        Write-Host "  * Mode Operasional  : $currentMode" -ForegroundColor White
        Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

        # Hitung durasi tunggu (Detik atau Menit tergantung parameter -TestingMode)
        $waitTimeInSeconds = if ($TestingMode) { $currentInterval } else { $currentInterval * 60 }
        
        # Countdown visual
        for ($i = $waitTimeInSeconds; $i -gt 0; $i--) {
            Write-Progress -Activity "Monitoring AQL Berjalan" -Status "Alarm berikutnya dalam $i detik..." -PercentComplete (($waitTimeInSeconds - $i) / $waitTimeInSeconds * 100)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "Monitoring AQL Berjalan" -Completed

        # Visual Indikator Alarm Terpemicu
        Write-Host "`n [!] ALARM BERBUNYI! SILAKAN MASUKKAN STATUS ANCAMAN [!]" -ForegroundColor Red -BackgroundColor Yellow
        
        # ----------------------------------------------------------------------
        # ALARM BUNYI CONTINUOUS (BACKGROUND THREAD)
        # ----------------------------------------------------------------------
        $alarmThread = [powershell]::Create().AddScript({
            while ($true) {
                [Console]::Beep(1000, 300) # Frekuensi 1000Hz, Durasi 300ms
                Start-Sleep -Milliseconds 400 # Jeda antar bunyi
            }
        })
        $null = $alarmThread.BeginInvoke() # Jalankan di latar belakang

        try {
            # Meminta Input Keputusan dari Analis (Alarm terus berbunyi selama loop input)
            $validInput = $false
            $severity   = ""

            while (-not $validInput) {
                Write-Host "`n Masukkan Status Ancaman Saat Ini:" -ForegroundColor Yellow
                Write-Host "   [C] Critical" -ForegroundColor Red
                Write-Host "   [H] High"     -ForegroundColor Magenta
                Write-Host "   [M] Medium"   -ForegroundColor DarkYellow
                Write-Host "   [L] Low"      -ForegroundColor Green
                
                $inputRaw = Read-Host "`n Pilihan Anda (C/H/M/L atau Critical/High/Medium/Low)"
                
                # Ekstrak karakter pertama jika pengguna mengetik kata utuh (misal: "Low" -> "L")
                if (-not [string]::IsNullOrWhiteSpace($inputRaw)) {
                    $severity = $inputRaw.Trim().Substring(0, 1).ToUpper()
                }

                if ($severity -in @('C', 'H', 'M', 'L')) {
                    $validInput = $true
                } else {
                    Write-Host " Pilihan tidak valid! Harap masukkan C, H, M, L atau nama statusnya." -ForegroundColor Red
                }
            }
        }
        finally {
            # Hentikan dan bersihkan thread alarm begitu input valid berhasil didapatkan
            if ($alarmThread) {
                $alarmThread.Stop()
                $alarmThread.Dispose()
            }
        }

        # Simpan state lama ke variabel histori sebelum di-update
        $lastInput    = $severity
        $lastInterval = $currentInterval
        $lastMode     = $currentMode

        # Evaluasi Matriks AQL & Transisi State
        $transition       = $aqlMatrix[$currentInterval][$severity]
        $nextInterval     = $transition.Next
        $nextMode         = $transition.Mode

        # Update State untuk Siklus Berikutnya
        $currentInterval = $nextInterval
        $currentMode     = $nextMode
        $loopCount       ++
    }
}

# Remediation
if ($F5Reset){
    routeF5Reset
}

