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
$TimePollingNormalSec = 7
# Interval polling rutin (cth: cek folder temp)

$TimeCleanupDelaySec  = 3
# Jeda waktu sebelum pembersihan/penghapusan file

$TimeSessionLockMs    = 200
# Interval sensor pengawasan keyboard/mouse (In-App Lock)

$TimeAqlMultiplier    = 60
# Pengali konversi AQL interval (menit ke detik)
