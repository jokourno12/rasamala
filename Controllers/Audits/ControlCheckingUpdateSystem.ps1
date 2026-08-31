. $PSScriptRoot\..\..\Config\Windows.ps1

function controlCheckingUpdateSystem{
    if ($IsWindows) {
        Write-Host "[Windows] Memeriksa Windows Update Agent..." @Net
        try {
            $session = New-Object -ComObject "Microsoft.Update.Session"
            $searcher = $session.CreateUpdateSearcher()
            
            $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0")
            $pendingCount = $searchResult.Updates.Count
            
            # Kumpulkan detail nama update
            $updateDetails = @()
            if ($pendingCount -gt 0) {
                foreach ($update in $searchResult.Updates) {
                    $updateDetails += $update.Title
                }
            }

            return [PSCustomObject]@{
                OS                  = "Windows"
                IsUpToDate          = ($pendingCount -eq 0)
                PendingUpdatesCount = $pendingCount
                Message             = if ($pendingCount -eq 0) { "Sistem fully updated." } else { "Ada $pendingCount update tertunda." }
                # Menggabungkan array menjadi satu string agar rapi saat ditampilkan di tabel
                PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join " | " } else { "N/A" } 
            }
        }
        catch {
            return [PSCustomObject]@{
                OS                  = "Windows"
                IsUpToDate          = $null
                PendingUpdatesCount = -1
                Message             = "Gagal memeriksa update: $($_.Exception.Message)"
                PendingDetails      = "N/A"
            }
        }
    }

    # 2. LINUX
    elseif ($IsLinux) {
        Write-Host "[Linux] Memeriksa Package Manager..." @Net
        $pendingCount = 0
        $pkgManager = "Unknown"
        $updateDetails = @()

        if (Get-Command apt-get -ErrorAction SilentlyContinue) {
            $pkgManager = "apt"
            # apt list --upgradable menampilkan daftar paket yang bisa diupdate
            $output = apt list --upgradable 2>/dev/null | Select-String -Pattern "/"
            if ($output) {
                $pendingCount = $output.Count
                foreach ($line in $output) {
                    # Format apt list biasanya: nama-paket/distro versi [upgradable...]
                    $pkgName = ($line.ToString() -split "/")[0]
                    $updateDetails += $pkgName
                }
            }
        }
        elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
            $pkgManager = "dnf"
            $null = dnf check-update 2>&1
            if ($LASTEXITCODE -eq 100) {
                $updates = (dnf check-update --quiet 2>&1) | Where-Object { $_ -match '\S+' }
                $pendingCount = $updates.Count
                foreach ($line in $updates) {
                    # Mengambil kata pertama (nama paket) dari baris dnf check-update
                    $pkgName = ($line.ToString() -split '\s+')[0]
                    $updateDetails += $pkgName
                }
            }
        }
        else {
            return [PSCustomObject]@{
                OS                  = "Linux"
                IsUpToDate          = $null
                PendingUpdatesCount = -1
                Message             = "Package manager tidak didukung/ditemukan."
                PendingDetails      = "N/A"
            }
        }

        return [PSCustomObject]@{
            OS                  = "Linux ($pkgManager)"
            IsUpToDate          = ($pendingCount -eq 0)
            PendingUpdatesCount = $pendingCount
            Message             = if ($pendingCount -eq 0) { "Sistem fully updated." } else { "Ada $pendingCount paket dapat di-upgrade." }
            PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join ", " } else { "N/A" }
        }
    }

    # 3. macOS
    elseif ($IsMacOS) {
        Write-Host "[macOS] Memeriksa Software Update CLI..." @Net
        $output = softwareupdate -l 2>&1 | Out-String
        $updateDetails = @()

        if ($output -match "No new software available") {
            return [PSCustomObject]@{
                OS                  = "macOS"
                IsUpToDate          = $true
                PendingUpdatesCount = 0
                Message             = "Sistem fully updated."
                PendingDetails      = "N/A"
            }
        }
        else {
            $matches = [regex]::Matches($output, "\*\s+Label:\s*(.*)")
            $pendingCount = $matches.Count
            
            if ($pendingCount -gt 0) {
                foreach ($match in $matches) {
                    $updateDetails += $match.Groups[1].Value.Trim()
                }
            } else {
                # Fallback jika Regex gagal tapi output tidak mengatakan "No new software"
                $pendingCount = 1
                $updateDetails += "Update terdeteksi, format label tidak dikenali."
            }

            return [PSCustomObject]@{
                OS                  = "macOS"
                IsUpToDate          = $false
                PendingUpdatesCount = $pendingCount
                Message             = "Ada $pendingCount update tertunda."
                PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join " | " } else { "N/A" }
            }
        }
    }
}