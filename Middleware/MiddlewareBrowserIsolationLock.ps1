. $PSScriptRoot\..\Config\Windows.ps1

function middlewareBrowserIsolationLock{
    Write-Host "[+] Mengaktifkan Sistem Pengaman Sesi (In-App Lock)..." @Net
    
    # <--- PERUBAHAN 1: Isolasi dependensi API Windows --->
    if ($IsWindows) {
        try {
            Add-Type @'
            using System;
            using System.Runtime.InteropServices;
            public class KeySensor {
                [DllImport("user32.dll")]
                public static extern short GetAsyncKeyState(int vKey);
            }
'@ -ErrorAction SilentlyContinue
            
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
        } catch { }
    }
    # <-------------------------------------------------->

    $sessionPin = "1234" 
    
    # Penyesuaian instruksi terminal berdasarkan OS
    if ($IsWindows) {
        Write-Host "    [i] PIN Sesi: $sessionPin (Tekan 'Alt + J' untuk mengunci)" @Dim
    } else {
        Write-Host "    [i] PIN Sesi: $sessionPin (Fokus di terminal ini lalu tekan 'Alt + J' untuk mengunci)" @Dim
    }

    $VK_MENU = 0x12
    $VK_J = 0x4A
    $isLocked = $false

    $lockFile = Join-Path ([System.IO.Path]::GetTempPath()) "rasamala_session.lock"

    # 2. Loop Pengawasan Utama
    while ($true) {
        Start-Sleep -Milliseconds 200

        $sessionAlive = $false

        if (Test-Path $lockFile) {
            $sessionAlive = $true
        }
        elseif ($null -ne $activeProcesses -and $activeProcesses.Count -gt 0) {
            $runningCount = (Get-Process -Id $activeProcesses.Id -ErrorAction SilentlyContinue).Count
            if ($runningCount -gt 0) {
                $sessionAlive = $true
            }
        }

        if (-not $sessionAlive) { 
            break 
        }

        # <--- PERUBAHAN 2: Deteksi input berdasarkan OS --->
        $triggerLock = $false

        if ($IsWindows) {
            # Windows: Global Hooking (berjalan walau browser sedang fokus)
            $alt_pressed = [KeySensor]::GetAsyncKeyState($VK_MENU) -band 0x8000
            $j_pressed = [KeySensor]::GetAsyncKeyState($VK_J) -band 0x8000
            if ($alt_pressed -and $j_pressed) { $triggerLock = $true }
        } else {
            # Linux/macOS Fallback: Terminal polling (membutuhkan fokus di terminal)
            if ([System.Console]::KeyAvailable) {
                $keyInfo = [System.Console]::ReadKey($true)
                if ($keyInfo.Key -eq [System.ConsoleKey]::J -and $keyInfo.Modifiers -match 'Alt') {
                    $triggerLock = $true
                }
            }
        }
        # <------------------------------------------------->

        if ($triggerLock -and -not $isLocked) {
            $isLocked = $true
            Write-Host "`n[!] Sesi Dikunci!" @Pen
            
            # <--- PERUBAHAN 3: Split perlakuan GUI (Windows) dan CLI (Linux) --->
            if ($IsWindows) {
                $overlay = New-Object System.Windows.Forms.Form
                $overlay.FormBorderStyle = 'None'
                $overlay.WindowState = 'Maximized'
                $overlay.TopMost = $true
                $overlay.BackColor = 'Black'
                $overlay.Opacity = 0.85 

                $overlay.Add_FormClosing({
                    param($sender, $e)
                    if ($overlay.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
                        $e.Cancel = $true
                    }
                })

                $overlay.ShowInTaskbar = $false 

                $imagePath = Join-Path (Split-Path $PSScriptRoot) "Helpers\rasamala-lock.png"
                $pictureBox = New-Object System.Windows.Forms.PictureBox
                $pictureBox.ImageLocation = $imagePath
                $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom 
                $pictureBox.Size = New-Object System.Drawing.Size(120, 120)
                    
                $screenWidth = [int][System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
                $posX = [int](($screenWidth / 2) - 60)
                $pictureBox.Location = New-Object System.Drawing.Point($posX, 150)
                    
                $overlay.Controls.Add($pictureBox)

                $lbl = New-Object System.Windows.Forms.Label
                $lbl.Text = "BROWSER LOCKED`nby S2025110106`nInput Session PIN"
                $lbl.Font = New-Object System.Drawing.Font("Consolas", 28, [System.Drawing.FontStyle]::Bold)
                $lbl.ForeColor = 'Red'
                $lbl.Dock = 'Top'
                $lbl.Height = 400
                $lbl.TextAlign = 'BottomCenter'
                $overlay.Controls.Add($lbl)

                $txtPin = New-Object System.Windows.Forms.TextBox
                $txtPin.Font = New-Object System.Drawing.Font("Consolas", 24)
                $txtPin.PasswordChar = '*'
                $txtPin.Width = 200
                $txtPin.Top = 450
                $txtPin.Left = ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 2) - 100
                $txtPin.TextAlign = 'Center'
                $overlay.Controls.Add($txtPin)

                $txtPin.Add_KeyDown({
                    if ($_.KeyCode -eq 'Enter') {
                        if ($txtPin.Text -eq $sessionPin) {
                            $overlay.DialogResult = [System.Windows.Forms.DialogResult]::OK
                            $overlay.Close()
                        } else {
                            $lbl.Text = "WRONG PIN!`nTry Again"
                            $txtPin.Text = ""
                        }
                    }
                })

                $overlay.Add_Shown({ $txtPin.Focus() })

                $overlay.ShowDialog() | Out-Null
                $overlay.Dispose()
            } 
            else {
                # Fungsi membekukan khusus Mesin Dalam (Anak Proses), membiarkan GUI (Induk) hidup
                function Suspend-BrowserEngines {
                    param([int]$ParentPID, [string]$Signal)
                    # Ambil daftar PID anak
                    $children = pgrep -P $ParentPID 2>$null
                    if ($children) {
                        foreach ($child in $children) {
                            # Rekursif ke bawah pohon proses
                            Suspend-BrowserEngines -ParentPID $child -Signal $Signal
                            # Tembak sinyal HANYA ke anak proses
                            & /bin/kill $Signal $child 2>$null
                        }
                    }
                }

                # 1. Eksekusi Hollow Freeze
                if ($null -ne $activeProcesses) {
                    foreach ($p in $activeProcesses) { 
                        Suspend-BrowserEngines -ParentPID $p.Id -Signal "-STOP"
                    }
                }

                # 2. Blokir interupsi keyboard (Ctrl+C akan ditolak/diabaikan)
                [console]::TreatControlCAsInput = $true

                # Linux/macOS Fallback: Terminal Lock (Membekukan eksekusi background terminal)
                Write-Host "`n==============================" -ForegroundColor Red
                Write-Host " BROWSER LOCKED by S2025110106" -ForegroundColor Red
                Write-Host "==============================" -ForegroundColor Red                                

                while ($true) {
                    $input = Read-Host "Input Session PIN"
                    if ($input -eq $sessionPin) {
                        break
                    }
                    Write-Host "WRONG PIN! Try Again.`n" -ForegroundColor Red
                }

                # 3. Lepaskan blokir keyboard
                [console]::TreatControlCAsInput = $false

                # 4. Cairkan (Resume) kembali mesin dalam peramban
                if ($null -ne $activeProcesses) {
                    foreach ($p in $activeProcesses) {
                        Suspend-BrowserEngines -ParentPID $p.Id -Signal "-CONT"
                    }
                }
            }
            # <------------------------------------------------------------------>

            while ([System.Console]::KeyAvailable) {
                $null = [System.Console]::ReadKey($true)
            }
            
            Write-Host "[v] PIN Benar. Tirai dibuka kembali." @App
            $isLocked = $false
            Start-Sleep -Seconds 1 
        }
    }
}
