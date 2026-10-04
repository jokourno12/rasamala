. $PSScriptRoot\..\..\Config\Windows.ps1

function controlProcessorStressTesting{
Write-Host "`n[+] Mempersiapkan Beban Kerja Absolut..." -ForegroundColor Cyan

$code = @"
using System;
using System.Threading.Tasks;
using System.Diagnostics;

public class EmpiricalBenchmark {
    public static double Run() {
        // Beban kerja: 4 Miliar kalkulasi floating-point kompleks
        long totalWork = 4000000000;
        int cores = Environment.ProcessorCount;
        long chunk = totalWork / cores;
        
        Stopwatch sw = Stopwatch.StartNew();
        double finalSum = 0;
        object lockObj = new object();

        Parallel.For(0, cores, i => {
            double result = 0;
            for(long j = 1; j <= chunk; j++) {
                // Kalkulasi berat untuk memforsir logic unit pada prosesor
                result += Math.Sqrt(j) + Math.Sin(j);
            }
            lock(lockObj) { finalSum += result; }
        });

        sw.Stop();
        return sw.Elapsed.TotalMilliseconds;
    }
}
"@

Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue

Write-Host "[+] Menghantam CPU dengan 4 Miliar Kalkulasi Paralel (100% Load)..." -ForegroundColor Yellow
Write-Host "[+] Harap tunggu, kipas PC Anda mungkin akan berputar lebih kencang...`n" -ForegroundColor Yellow

$waktuMs = [EmpiricalBenchmark]::Run()
$waktuDetik = [math]::Round($waktuMs / 1000, 2)

$score = [math]::Round(4000000000 /$waktuMs, 0)

$kategori = ""
$warna = "White"

if ($waktuDetik -le 4.5) {
    $kategori = "WORKSTATION / ENTHUSIAST TIER"
    $warna = "Magenta"
} elseif ($waktuDetik -le 10.0) {
    $kategori = "CREATIVE / HIGH-END TIER"
    $warna = "Green"
} elseif ($waktuDetik -le 25.0) {
    $kategori = "PRODUCTIVITY / MID-RANGE TIER"
    $warna = "Cyan"
} else {
    $kategori = "ENTRY LEVEL TIER"
    $warna = "Gray"
}

Write-Host "==================================================" -ForegroundColor White
Write-Host " HASIL KEKUATAN MURNI (EMPIRICAL STRESS TEST)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor White
Write-Host " Waktu Selesai : $waktuDetik detik"
Write-Host " Skor Performa : $score Poin"
Write-Host "--------------------------------------------------"
Write-Host " KELAS PC ANDA : $kategori" -ForegroundColor $warna
Write-Host "==================================================`n" -ForegroundColor White
}