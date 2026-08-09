function helperSlaInfo {
    param([string]$Client = 'All')

    $taspen = @"
========================================================================
             INFORMASI SLA - PT TASPEN (PERSERO) TAHUN 2025             
========================================================================
  Severity Level        | Response Time | Resolution Time
  ----------------------+---------------+-------------------------------
  Severity 1 (Critical) | 15 Menit      | 1 Jam
  Severity 2 (High)     | 30 Menit      | 2 Jam
  Severity 3 (Medium)   | 45 Menit      | 4 Jam
  Severity 4 (Low)      | 60 Menit      | 12 Jam

  Catatan Metrik:
  * Response Time   : Waktu tanggap awal setelah laporan diterima.
  * Resolution Time : Waktu penyelesaian insiden / pemenuhan permintaan.
"@

    $pertamina = @"
========================================================================
                    INFORMASI SLA - PERTAMINA TAHUN 2026                       
========================================================================
  Level    | Response | Resolution | Deskripsi Kriteria Insiden
  ---------+----------+------------+------------------------------------
  Critical | 30 Menit | 1 Jam      | Kebocoran data / Total outage
  High     | 30 Menit | 2 Jam      | Kebocoran data / Partial outage
  Medium   | 60 Menit | 4 Jam      | Partial outage / Tanpa kebocoran
  Low      | 60 Menit | 8 Jam      | Deteksi threat / Non-impact
"@

    if ($Client -eq 'Taspen') {
        Write-Host $taspen -ForegroundColor Cyan
    }
    elseif ($Client -eq 'Pertamina') {
        Write-Host $pertamina -ForegroundColor Yellow
    }
    else {
        Write-Host $taspen -ForegroundColor Cyan
        Write-Host "`n"
        Write-Host $pertamina -ForegroundColor Yellow
    }
}

