#GLOBAL THEMES
$Pen = @{ ForegroundColor = 'Red' }
# Kritis, Error, & Tindakan Destruktif (misal: Force Cleanup / Sesi Crash)

$Net = @{ ForegroundColor = 'Blue' }
# Informasi Umum & Penanda Langkah Awal / Header Proses

$Inc = @{ ForegroundColor = 'Magenta' }
# Status Khusus, Proses Background, atau Sub-sistem Tersembunyi

$App = @{ ForegroundColor = 'Green' }
# Keberhasilan (Success) & Status Normal / Aman Berjalan

$Cha = @{ ForegroundColor = 'DarkYellow' }  
# Peringatan (Warning) & Kondisi Kehati-hatian / Menunggu (Caution)

$Dim = @{ ForegroundColor = 'DarkGray' }
# Detail Teknis, Instruksi Minor, & Teks Background (Tidak mendominasi visual)


#GLOBAL TIMES
# 1. Eksekusi & Timeout Proses (Operations & Remediations)
$TimeExecShortSec     = 10      # Timeout perintah lokal cepat (cek reg, service status)
$TimeExecLongSec      = 300     # Timeout operasi berat (scan disk, instalasi patch)
$TimeProcessWaitSec   = 30      # Batas tunggu proses eksternal sebelum dibunuh (kill)

# 2. Jaringan & Komunikasi (API, Download, Update)
$TimeNetConnectSec    = 5       # Timeout tes koneksi / ping / handshake API
$TimeNetRequestSec    = 30      # Timeout unduh payload / upload log audit
$TimeRetryDelaySec    = 3       # Jeda antar percobaan ulang (retry mechanism)

# 3. Sesi & Keamanan (Middleware & Security)
$TimeSessionLockMs    = 200     # Interval sensor keyboard / mouse (In-App Lock)
$TimeInactivityMin    = 15      # Waktu idle sebelum sesi dikunci otomatis
$TimeLockGraceSec     = 1       # Jeda mencegah pemicuan ganda (double-trigger)

# 4. Polling & Pemantauan (Background Jobs / Audits)
$TimePollingFastSec   = 2       # Polling kondisi krusial (cek status lock/kill switch)
$TimePollingNormalSec = 7       # Polling rutin (seperti cek sisa folder temp)
$TimePollingSlowSec   = 60      # Audit berkala di latar belakang

# 5. Retensi & Pembersihan (Self-Healing & Cleanup)
$TimeCleanupDelaySec  = 3       # Jeda sebelum menghapus file/folder sementara
$TimeStaleFolderHours = 24      # Batas umur folder temp sebelum dianggap "stale/crash"
