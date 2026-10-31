function beaconAqlMonitoring{
    #return "Hello AQL monitoring"
    $view = [Terminal.Gui.View]::new()
    $view.Width = [Terminal.Gui.Dim]::Fill()
    $view.Height = [Terminal.Gui.Dim]::Fill()

    # Status persisten untuk AQL Job
    if ($null -eq $script:aqlJobRunning) { $script:aqlJobRunning = $false }
    if ($null -eq $script:currentAqlJob) { $script:currentAqlJob = $null }

    $lblStatus = [Terminal.Gui.Label]::new("Status: [ READY ] Menunggu Tes AQL")
    $lblStatus.X = 1
    $lblStatus.Y = 1

    $btnAction = [Terminal.Gui.Button]::new("Jalankan Test AQL")
    $btnAction.X = 1
    $btnAction.Y = 3

    $txtLog = [Terminal.Gui.TextView]::new()
    $txtLog.X = 1
    $txtLog.Y = 5
    $txtLog.Width = [Terminal.Gui.Dim]::Fill(1)
    $txtLog.Height = [Terminal.Gui.Dim]::Fill(1)
    $txtLog.ReadOnly = $true

    $btnAction.add_Clicked({
        if (-not $script:aqlJobRunning) {
            $script:aqlJobRunning = $true
            $btnAction.Text = "Hentikan Test"
            $lblStatus.Text = "Status: [ RUNNING ] Job AQL Berjalan di Background"

            $txtLog.Text = "[*] Memulai Background Job AQL...`n"

            # Command percobaan konkuren untuk AQL
            $script:currentAqlJob = Start-Job -ScriptBlock {
                for ($i = 1; $i -le 50; $i++) {
                    [PSCustomObject]@{ Time = (Get-Date).ToString("HH:mm:ss"); Message = "AQL Test Loop #$i" }
                    Start-Sleep -Seconds 1
                }
            }

            # Polling hasil job menggunakan MainLoop agar UI tidak freeze
            [Terminal.Gui.Application]::MainLoop.AddTimeout([System.TimeSpan]::FromMilliseconds(500), {
                param()
                if ($script:aqlJobRunning -and $null -ne $script:currentAqlJob) {
                    $newData = Receive-Job -Job $script:currentAqlJob
                    if ($newData) {
                        $formatted = foreach ($item in $newData) { "[$($item.Time)] $($item.Message)" }
                        $txtLog.Text = $txtLog.Text.ToString() + ($formatted -join "`n") + "`n"
                        $view.SetNeedsDisplay()
                    }

                    if ($script:currentAqlJob.State -ne 'Running') {
                        $script:aqlJobRunning = $false
                        $btnAction.Text = "Jalankan Test AQL"
                        $lblStatus.Text = "Status: [ READY ] Selesai"
                        Remove-Job -Job $script:currentAqlJob -Force
                        $script:currentAqlJob = $null
                        return $false
                    }
                    return $true
                }
                return $false
            })
        } else {
            $script:aqlJobRunning = $false
            if ($null -ne $script:currentAqlJob) {
                Stop-Job -Job $script:currentAqlJob
                Remove-Job -Job $script:currentAqlJob -Force
                $script:currentAqlJob = $null
            }
            $btnAction.Text = "Jalankan Test AQL"
            $lblStatus.Text = "Status: [ STOPPED ] Dihentikan User"
            $txtLog.Text = $txtLog.Text.ToString() + "`n[-] Test dihentikan.`n"
        }
        $view.SetNeedsDisplay()
    }.GetNewClosure())

    $view.Add([Terminal.Gui.View[]]@($lblStatus, $btnAction, $txtLog))
    return $view
}