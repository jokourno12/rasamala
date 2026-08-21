function middlewareBrowserIsolationLock{
    Write-Host "[+] Mengaktifkan Sistem Pengaman Sesi (In-App Lock)..." -ForegroundColor Yellow
    
    # 1. Memuat Modul Sensor & Modul Grafis (GUI)
    try {
        Add-Type @'
        using System;
        using System.Runtime.InteropServices;
        public class KeySensor {
            [DllImport("user32.dll")]
            public static extern short GetAsyncKeyState(int vKey);
        }
'@ -ErrorAction SilentlyContinue
        
        # Load .NET Forms & Drawing untuk membuat Layar Penutup
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    } catch { }

    $sessionPin = "1234" 
    Write-Host "    [i] PIN Sesi: $sessionPin (Tekan 'Alt + J' untuk mengunci)" -ForegroundColor DarkGray

    $VK_MENU = 0x12
    $VK_J = 0x4A
    $isLocked = $false

    # 2. Loop Pengawasan Utama
    while ($true) {
        Start-Sleep -Milliseconds 200

        $runningCount = (Get-Process -Id $activeProcesses.Id -ErrorAction SilentlyContinue).Count
        if ($runningCount -eq 0) { break }

        $alt_pressed = [KeySensor]::GetAsyncKeyState($VK_MENU) -band 0x8000
        $j_pressed = [KeySensor]::GetAsyncKeyState($VK_J) -band 0x8000

        # Jika Alt + J ditekan
        if ($alt_pressed -and $j_pressed -and -not $isLocked) {
            $isLocked = $true
            Write-Host "`n[!] Sesi Dikunci! Menampilkan Overlay..." -ForegroundColor Red
            
            # --- MEMBANGUN LAYAR PENUTUP (OVERLAY) ---
            $overlay = New-Object System.Windows.Forms.Form
            $overlay.FormBorderStyle = 'None'
            $overlay.WindowState = 'Maximized'
            $overlay.TopMost = $true
            $overlay.BackColor = 'Black'
            $overlay.Opacity = 0.85 # 85% Gelap, browser masih remang-remang di belakang

            # --- TAMBAHAN: BLOKIR ALT+F4 ---
            $overlay.Add_FormClosing({
                param($sender, $e)
                # Jika DialogResult bukan OK (berarti tombol tutup ditekan, bukan karena PIN benar),
                # maka batalkan perintah penutupan (Cancel).
                if ($overlay.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
                    $e.Cancel = $true
                }
            })

            # Opsional: Agar tidak bisa ditutup via klik kanan di Taskbar
            $overlay.ShowInTaskbar = $false 
            # ------------------------------

            # Tambahkan PictureBox
            $imagePath = Join-Path (Split-Path $PSScriptRoot) "Helpers\rasamala-lock.png"
            $pictureBox = New-Object System.Windows.Forms.PictureBox
            $pictureBox.ImageLocation = $imagePath
            $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom 
            $pictureBox.Size = New-Object System.Drawing.Size(120, 120)
                
            # --- PERBAIKAN: Hitung posisi secara bertahap agar tidak terjadi error [System.Object[]] ---
            $screenWidth = [int][System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
            $posX = [int](($screenWidth / 2) - 60)
            $pictureBox.Location = New-Object System.Drawing.Point($posX, 150)
                
            $overlay.Controls.Add($pictureBox)

            # Label "BROWSER LOCKED"
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = "BROWSER LOCKED`nby S2025110106`nInput Session PIN"
            $lbl.Font = New-Object System.Drawing.Font("Consolas", 28, [System.Drawing.FontStyle]::Bold)
            $lbl.ForeColor = 'Red'
            $lbl.Dock = 'Top'
            $lbl.Height = 400
            $lbl.TextAlign = 'BottomCenter'
            $overlay.Controls.Add($lbl)

            # Kolom Input PIN
            $txtPin = New-Object System.Windows.Forms.TextBox
            $txtPin.Font = New-Object System.Drawing.Font("Consolas", 24)
            $txtPin.PasswordChar = '*'
            $txtPin.Width = 200
            $txtPin.Top = 450
            # Posisi rata tengah secara dinamis
            $txtPin.Left = ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 2) - 100
            $txtPin.TextAlign = 'Center'
            $overlay.Controls.Add($txtPin)

            # Logika saat tombol Enter ditekan pada kolom PIN
            $txtPin.Add_KeyDown({
                if ($_.KeyCode -eq 'Enter') {
                    if ($txtPin.Text -eq $sessionPin) {
                        # PIN Benar: Tutup overlay
                        $overlay.DialogResult = [System.Windows.Forms.DialogResult]::OK
                        $overlay.Close()
                    } else {
                        # PIN Salah: Kosongkan kolom dan beri peringatan
                        $lbl.Text = "WRONG PIN!`nTry Again"
                        $txtPin.Text = ""
                    }
                }
            })

            # Fokus kursor otomatis ke kolom PIN saat layar muncul
            $overlay.Add_Shown({ $txtPin.Focus() })

            # Menahan eksekusi skrip sampai form overlay ditutup
            $overlay.ShowDialog() | Out-Null
            # ----------------------------------------
            
            Write-Host "[v] PIN Benar. Tirai dibuka kembali." -ForegroundColor Green
            $isLocked = $false
            Start-Sleep -Seconds 1 # Jeda agar tidak langsung terkunci ganda
        }
    }
}