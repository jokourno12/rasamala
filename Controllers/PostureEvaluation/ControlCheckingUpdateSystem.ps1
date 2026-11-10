function controlCheckingUpdateSystem{
    if ($IsWindows) {
        Write-Host "[Windows] Checking Windows Update Agent..." @Net
        try {
            $session = New-Object -ComObject "Microsoft.Update.Session"
            $searcher = $session.CreateUpdateSearcher()
            
            $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0")
            $pendingCount = $searchResult.Updates.Count
            
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
                Message             = if ($pendingCount -eq 0) { "System fully updated." } else { "$pendingCount pending update" }

                PendingDetails      = if ($updateDetails.Count -gt 0) { $updateDetails -join " | " } else { "N/A" } 
            }
        }
        catch {
            return [PSCustomObject]@{
                OS                  = "Windows"
                IsUpToDate          = $null
                PendingUpdatesCount = -1
                Message             = "Failed to check for updates: $($_.Exception.Message)"
                PendingDetails      = "N/A"
            }
        }
    }

    elseif ($IsLinux) {
        Write-Host "[Linux] Checking Package Manager..." @Net
        $pendingCount = 0
        $pkgManager = "Unknown"
        $updateDetails = @()

        if (Get-Command apt-get -ErrorAction SilentlyContinue) {
            $pkgManager = "apt"
            
            $output = @(& apt-get -s upgrade 2>&1 | Select-String -Pattern "^Inst ")
            if ($output.Count -gt 0) {
                $pendingCount = $output.Count
                foreach ($line in $output) {
                    $pkgName = ($line.ToString() -split '\s+')[1]
                    $updateDetails += $pkgName
                }
            }
        }
        elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
            $pkgManager = "dnf"
            $null = dnf check-update 2>&1
            if ($LASTEXITCODE -eq 100) {
                $updates = @((dnf check-update --quiet 2>&1) | Where-Object { $_ -match '\S+' })
                $pendingCount = $updates.Count
                foreach ($line in $updates) {
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

    elseif ($IsMacOS) {
        Write-Host "[macOS] Checking CLI Software Updates..." @Net
        $output = softwareupdate -l 2>&1 | Out-String
        $updateDetails = @()

        if ($output -match "No new software available" -or $output -match "No updates available") {
            return [PSCustomObject]@{
                OS                  = "macOS"
                IsUpToDate          = $true
                PendingUpdatesCount = 0
                Message             = "Sistem fully updated."
                PendingDetails      = "N/A"
            }
        }
        else {
            $lines = $output -split "`n" | Where-Object { $_ -match "\*\s+" -or $_ -match "Label:\s*" }
            foreach ($line in $lines) {
                $cleanLine = ($line -replace "\*|Label:", "").Trim()
                if ($cleanLine) { $updateDetails += $cleanLine }
            }

            $pendingCount = if ($updateDetails.Count -gt 0) { $updateDetails.Count } else { 1 }

            return [PSCustomObject]@{
                OS                  = "macOS"
                IsUpToDate          = $false
                PendingUpdatesCount = $pendingCount
                Message             = "$pendingCount pending update"
                PendingDetails      = if ($updateDetails.Count -gt 0) { ($updateDetails | Select-Object -Unique) -join " | " } else { "Update detected, label format not recognized." }
            }
        }
    }
}