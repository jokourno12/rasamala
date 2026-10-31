function beaconBrowserIsolation{
    #return "Hello isolation"
    $view = [Terminal.Gui.View]::new()
    $view.Width = [Terminal.Gui.Dim]::Fill()
    $view.Height = [Terminal.Gui.Dim]::Fill()

    # Status persisten untuk Isolation Job
    if ($null -eq $script:isoJobRunning) { $script:isoJobRunning = $false }
    if ($null -eq $script:currentIsoJob) { $script:currentIsoJob = $null }

    $lblStatus = [Terminal.Gui.Label]::new("Status: [ READY ] Menunggu Tes Isolation")
    $lblStatus.X = 1
    $lblStatus.Y = 1

    $btnAction = [Terminal.Gui.Button]::new("Jalankan Test Isolation")
    $btnAction.X = 1
    $btnAction.Y = 3

    $txtLog = [Terminal.Gui.TextView]::new()
    $txtLog.X = 1
    $txtLog.Y = 5
    $txtLog.Width = [Terminal.Gui.Dim]::Fill(1)
    $txtLog.Height = [Terminal.Gui.Dim]::Fill(1)
    $txtLog.ReadOnly = $true

    $btnAction.add_Clicked({
        if (-not $script:isoJobRunning) {
            $script:isoJobRunning = $true
            $btnAction.Text = "Hentikan Test"
            $lblStatus.Text = "Status: [ RUNNING ] Job Isolation Berjalan di Background"

            $txtLog.Text = "[*] Memulai Background Job Isolation...`n"

            # Command percobaan konkuren untuk Isolation
            $script:currentIsoJob = Start-Job -ScriptBlock {
                for ($j = 1; $j -le 50; $j++) {
                    [PSCustomObject]@{ Time = (Get-Date).ToString("HH:mm:ss"); Message = "Isolation Workspace Active #$j" }
                    Start-Sleep -Seconds 3
                }
            }

            # Polling hasil job menggunakan MainLoop agar UI tidak freeze
            [Terminal.Gui.Application]::MainLoop.AddTimeout([System.TimeSpan]::FromMilliseconds(500), {
                param()
                if ($script:isoJobRunning -and $null -ne $script:currentIsoJob) {
                    $newData = Receive-Job -Job $script:currentIsoJob
                    if ($newData) {
                        $formatted = foreach ($item in $newData) { "[$($item.Time)] $($item.Message)" }
                        $txtLog.Text = $txtLog.Text.ToString() + ($formatted -join "`n") + "`n"
                        $view.SetNeedsDisplay()
                    }

                    if ($script:currentIsoJob.State -ne 'Running') {
                        $script:isoJobRunning = $false
                        $btnAction.Text = "Jalankan Test Isolation"
                        $lblStatus.Text = "Status: [ READY ] Selesai"
                        Remove-Job -Job $script:currentIsoJob -Force
                        $script:currentIsoJob = $null
                        return $false
                    }
                    return $true
                }
                return $false
            })
        } else {
            $script:isoJobRunning = $false
            if ($null -ne $script:currentIsoJob) {
                Stop-Job -Job $script:currentIsoJob
                Remove-Job -Job $script:currentIsoJob -Force
                $script:currentIsoJob = $null
            }
            $btnAction.Text = "Jalankan Test Isolation"
            $lblStatus.Text = "Status: [ STOPPED ] Dihentikan User"
            $txtLog.Text = $txtLog.Text.ToString() + "`n[-] Test dihentikan.`n"
        }
        $view.SetNeedsDisplay()
    }.GetNewClosure())

    $view.Add([Terminal.Gui.View[]]@($lblStatus, $btnAction, $txtLog))
    return $view
}