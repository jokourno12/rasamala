. $PSScriptRoot\..\..\Config\Windows.ps1

function controlProcessorStressTesting{
Write-Host "`n[+] Preparing for Absolute Workload..." -ForegroundColor Cyan

$code = @"
using System;
using System.Threading.Tasks;
using System.Diagnostics;

public class EmpiricalBenchmark {
    public static double Run() {
        long totalWork = 4000000000;
        int cores = Environment.ProcessorCount;
        long chunk = totalWork / cores;
        
        Stopwatch sw = Stopwatch.StartNew();
        double finalSum = 0;
        object lockObj = new object();

        Parallel.For(0, cores, i => {
            double result = 0;
            for(long j = 1; j <= chunk; j++) {
                result += Math.Sqrt(j) + Math.Sin(j);
            }
            lock(lockObj) { finalSum += result; }
        });

        sw.Stop();
        return sw.Elapsed.TotalMilliseconds;
    }
}
"@

if (-not ("EmpiricalBenchmark" -as [type])) {
    Add-Type -TypeDefinition $code -ErrorAction Stop
}

Write-Host "[+] Hitting the CPU with 4 Billion Parallel Calculations (100% Load)..." -ForegroundColor Yellow
Write-Host "[+] Please wait, your PC fan will probably spin faster...`n" -ForegroundColor Yellow

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
Write-Host " EMPIRICAL STRESS TEST " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor White
Write-Host " Time Completed    : $waktuDetik detik"
Write-Host " Performance Score : $score Poin"
Write-Host "--------------------------------------------------"
Write-Host " YOUR PC CLASS : $kategori" -ForegroundColor $warna
Write-Host "==================================================`n" -ForegroundColor White
}