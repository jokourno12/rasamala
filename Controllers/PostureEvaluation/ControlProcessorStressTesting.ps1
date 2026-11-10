function controlProcessorStressTesting{
    if ($IsWindows) {
        Write-Host "`n[Windows] Testing Processor Performance..." @Net
    } elseif ($IsLinux) {
        Write-Host "`n[Linux] Testing Processor Performance..." @Net
    } else {
        Write-Host "`n[*] Testing Processor Performance..." @Net
    }

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

    $waktuMs = [EmpiricalBenchmark]::Run()
    $waktuDetik = [math]::Round($waktuMs / 1000, 2)

    $score = [math]::Round(4000000000 /$waktuMs, 0)

    $kategori = ""

    if ($waktuDetik -le 4.5) {$kategori = "WORKSTATION / ENTHUSIAST TIER"
    } elseif ($waktuDetik -le 10.0) {$kategori = "CREATIVE / HIGH-END TIER"
    } elseif ($waktuDetik -le 25.0) {$kategori = "PRODUCTIVITY / MID-RANGE TIER"
    } else {
        $kategori = "ENTRY LEVEL TIER"
    }

    $osName = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } elseif ($IsMacOS) { "macOS" } else { "Unknown" }

    $processorResult = [PSCustomObject]@{
        OS                   = $osName
        Module               = "Processor Stress Test"
        TimeCompletedSeconds = $waktuDetik
        PerformanceScore     = $score
        PCClass              = $kategori
    }

    return $processorResult
}