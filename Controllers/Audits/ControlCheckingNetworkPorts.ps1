function controlCheckingNetworkPorts{
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa Listening Ports TCP..." -ForegroundColor Cyan
        try {
            # Menggunakan Get-NetTCPConnection (PowerShell native)
            $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop
            # Ekstrak port, hilangkan duplikat, dan urutkan
            $ports = $connections.LocalPort | Select-Object -Unique | Sort-Object
            $portList = if ($ports) { $ports -join ", " } else { "None" }

            return [PSCustomObject]@{
                OS             = "Windows"
                OpenPortsCount = if ($ports) { $ports.Count } else { 0 }
                ListeningPorts = $portList
                Message        = "Port TCP terbuka dan siap menerima koneksi (LISTEN)."
            }
        }
        catch {
            return [PSCustomObject]@{
                OS             = "Windows"
                OpenPortsCount = -1
                ListeningPorts = "N/A"
                Message        = "Gagal membaca Listening Ports. Pastikan hak akses cukup."
            }
        }
    }
    elseif ($IsLinux) {
        Write-Host "[Linux] Memeriksa Listening Ports TCP (ss)..." -ForegroundColor Cyan
        $ports = @()
        if (Get-Command ss -ErrorAction SilentlyContinue) {
            # Parsing output dari ss (Socket Statistics)
            $lines = ss -tln 2>/dev/null | Select-String "LISTEN"
            foreach ($line in $lines) {
                # Menggunakan regex untuk menangkap angka port setelah tanda titik dua (contoh: 0.0.0.0:22)
                if ($line -match ":(\d+)\s+") {
                    $ports += [int]$Matches[1]
                }
            }
        }
        
        $ports = $ports | Select-Object -Unique | Sort-Object | Where-Object { $_ -ne $null }
        $portList = if ($ports) { $ports -join ", " } else { "None" }

        return [PSCustomObject]@{
            OS             = "Linux"
            OpenPortsCount = if ($ports) { $ports.Count } else { 0 }
            ListeningPorts = $portList
            Message        = "Port TCP terbuka (LISTEN) yang ditemukan via utilitas 'ss'."
        }
    }
    elseif ($IsMacOS) {
        Write-Host "[macOS] Memeriksa Listening Ports TCP (lsof)..." -ForegroundColor Cyan
        $ports = @()
        if (Get-Command lsof -ErrorAction SilentlyContinue) {
            # Menjalankan lsof untuk mencari TCP LISTEN dan mencegah resolusi DNS (-n)
            $lines = lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
            foreach ($line in $lines) {
                if ($line -match ":(\d+)\s+\(LISTEN") {
                    $ports += [int]$Matches[1]
                }
            }
        }
        
        $ports = $ports | Select-Object -Unique | Sort-Object | Where-Object { $_ -ne $null }
        $portList = if ($ports) { $ports -join ", " } else { "None" }

        return [PSCustomObject]@{
            OS             = "macOS"
            OpenPortsCount = if ($ports) { $ports.Count } else { 0 }
            ListeningPorts = $portList
            Message        = "Port TCP terbuka (LISTEN) yang ditemukan via utilitas 'lsof'."
        }
    }
}