function beaconBrowserIsolation{
    #return "Hello isolation"
    $view = [Terminal.Gui.View]::new()
    $view.Width = [Terminal.Gui.Dim]::Fill()
    $view.Height = [Terminal.Gui.Dim]::Fill()

    # Status persisten untuk eksekusi terminal manual
    if ($null -eq $script:manualJob) { $script:manualJob = $null }

    # [1] Baris Input Terminal Manual (Digeser ke atas)
    $lblInput = [Terminal.Gui.Label]::new("PS> ")
    $lblInput.X = 1
    $lblInput.Y = 1

    $txtInput = [Terminal.Gui.TextField]::new("")
    $txtInput.X = [Terminal.Gui.Pos]::Right($lblInput)
    $txtInput.Y = 1
    $txtInput.Width = [Terminal.Gui.Dim]::Fill(1)

    # [2] Baris Log Stream
    $txtLog = [Terminal.Gui.TextView]::new()
    $txtLog.X = 1
    $txtLog.Y = 3
    $txtLog.Width = [Terminal.Gui.Dim]::Fill(1)
    $txtLog.Height = [Terminal.Gui.Dim]::Fill(1)
    $txtLog.ReadOnly = $true

    # ---------------------------------------------------------
    # EVENT: EKSEKUSI PERINTAH MANUAL (ENTER DI TEXTFIELD)
    # ---------------------------------------------------------
    $txtInput.add_KeyPress({
        param($e)
        if ($e.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
            $command = $txtInput.Text.ToString().Trim()
            
            if (-not [string]::IsNullOrWhiteSpace($command)) {
                
                # Intersepsi perintah manipulasi UI (Terminal Tiruan)
                if ($command.ToLower() -eq 'clear' -or $command.ToLower() -eq 'cls') {
                    $txtLog.Text = ""
                    $txtInput.Text = ""
                    $view.SetNeedsDisplay()
                    $e.Handled = $true 
                    return
                }

                $txtLog.Text = $txtLog.Text.ToString() + "PS> $command`n"
                
                # Eksekusi latar belakang dengan aliran real-time
                $script:manualJob = Start-ThreadJob -ScriptBlock {
                    param($cmd)
                    Invoke-Expression "$cmd *>&1" | ForEach-Object { "$_" }
                } -ArgumentList $command

                # Polling hasil eksekusi manual agar UI tidak freeze
                [Terminal.Gui.Application]::MainLoop.AddTimeout([System.TimeSpan]::FromMilliseconds(500), {
                    param()
                    if ($null -ne $script:manualJob) {
                        $output = Receive-Job -Job $script:manualJob
                        if ($output) {
                            $txtLog.Text = $txtLog.Text.ToString() + ($output -join "`n") + "`n"
                            $view.SetNeedsDisplay()
                        }

                        if ($script:manualJob.State -ne 'Running') {
                            Remove-Job -Job $script:manualJob -Force
                            $script:manualJob = $null
                            return $false # Hentikan timer ini
                        }
                        return $true # Lanjutkan timer
                    }
                    return $false
                })

                $txtInput.Text = ""
                $view.SetNeedsDisplay()
            }
            $e.Handled = $true 
        }
    }.GetNewClosure())

    # [3] Memasukkan elemen ke dalam View
    $view.Add([Terminal.Gui.View[]]@($lblInput, $txtInput, $txtLog))
    return $view
}