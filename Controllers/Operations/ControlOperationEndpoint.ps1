function controlOperationEndpoint{
    # 1. Resolusi path relatif ke Helpers\Lib
    $libDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\Helpers\Lib"))
    $nstackDll = Join-Path $libDir "NStack.dll"
    $guiDll    = Join-Path $libDir "Terminal.Gui.dll"

    # 2. Buka pemblokiran & Muat Assembly
    Unblock-File -Path $nstackDll -ErrorAction SilentlyContinue
    Unblock-File -Path $guiDll -ErrorAction SilentlyContinue

    [System.Reflection.Assembly]::LoadFrom($nstackDll) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($guiDll) | Out-Null

    # 3. Inisialisasi TUI
    [Terminal.Gui.Application]::Init()

    # 4. Konstruksi Skema Warna (Dark Gray Theme)
    Write-Host -NoNewline "`e]4;2;#1B5E20`a"
    
    # Menimpa Color 3 (Brown/Yellow) menjadi Cokelat Batang Kayu Tua (Hex: #3E2723)
    #Write-Host -NoNewline "`e]4;3;#3E2723`a"


    # 4. Konstruksi Skema Warna (Sekarang Green dan Brown menggunakan warna Hex di atas)
    $treeScheme = [Terminal.Gui.ColorScheme]::new()
    
    $normalAttr    = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Green, [Terminal.Gui.Color]::Brown)
    $focusAttr     = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Brown, [Terminal.Gui.Color]::Green)
    $hotNormalAttr = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::White, [Terminal.Gui.Color]::Brown)
    $hotFocusAttr  = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::White, [Terminal.Gui.Color]::Green)

    $treeScheme.Normal    = $normalAttr
    $treeScheme.Focus     = $focusAttr
    $treeScheme.HotNormal = $hotNormalAttr
    $treeScheme.HotFocus  = $hotFocusAttr

    [Terminal.Gui.Colors]::Base = $treeScheme
    [Terminal.Gui.Colors]::TopLevel = $treeScheme
    $top = [Terminal.Gui.Application]::Top
    $top.ColorScheme = $treeScheme

    # ---------------------------------------------------------
    # MEKANISME KUNCI KELUAR (ANTI CTRL+Q / SALAH PENCET)
    # ---------------------------------------------------------
    $script:isSafeToExit = $false

    $top.add_Closing({
        param($eventArgs)
        # Jika tombol Exit belum diklik ($isSafeToExit masih False),
        # maka batalkan perintah keluar dari shortcut apapun.
        if ($script:isSafeToExit -eq $false) {
            $eventArgs.Cancel = $true
        }
    })

    # ---------------------------------------------------------
    # MEMBANGUN LAYOUT UTAMA (4 PANEL)
    # ---------------------------------------------------------
    $win = [Terminal.Gui.Window]::new("")
    $win.X = 0
    $win.Y = 0
    $win.Width = [Terminal.Gui.Dim]::Fill()
    $win.Height = [Terminal.Gui.Dim]::Fill()

    # [1. HEADER]
    $headerPanel = [Terminal.Gui.FrameView]::new(" RASAMALA COCKPIT - OPERATION MODULE ")
    $headerPanel.X = 0
    $headerPanel.Y = 0
    $headerPanel.Width = [Terminal.Gui.Dim]::Fill()
    $headerPanel.Height = 3 

    $lblHeaderInfo = [Terminal.Gui.Label]::new(" Host: ENDPOINT-01   |   Status: READY   |   17:52 WIB ")
    $lblHeaderInfo.X = 1
    $lblHeaderInfo.Y = 0
    $headerPanel.Add($lblHeaderInfo)
    
    # [2. NAVIGATION]
    $navPanel = [Terminal.Gui.FrameView]::new(" NAVIGATION ")
    $navPanel.X = 0
    $navPanel.Y = [Terminal.Gui.Pos]::Bottom($headerPanel)
    $navPanel.Width = 25
    $navPanel.Height = [Terminal.Gui.Dim]::Fill(4)

    $menuItems = [string[]]@("Metrics", "Isolation", "Tunnel", "AQL Mon", "JS Runtime")
    $menuList = [Terminal.Gui.ListView]::new($menuItems)
    $menuList.X = 0
    $menuList.Y = 0
    $menuList.Width = [Terminal.Gui.Dim]::Fill()
    $menuList.Height = [Terminal.Gui.Dim]::Fill()
    $navPanel.Add($menuList)

    # [3. CONTENT]
    $contentPanel = [Terminal.Gui.FrameView]::new(" WORKSPACE ")
    $contentPanel.X = [Terminal.Gui.Pos]::Right($navPanel)
    $contentPanel.Y = [Terminal.Gui.Pos]::Bottom($headerPanel)
    $contentPanel.Width = [Terminal.Gui.Dim]::Fill()
    $contentPanel.Height = [Terminal.Gui.Dim]::Fill(4)

    $lblTitle = [Terminal.Gui.Label]::new("Modul Aktif: [ Belum Ada Data ]")
    $lblTitle.X = 2
    $lblTitle.Y = 2

    $btnRun = [Terminal.Gui.Button]::new(" [ TEST TOMBOL ] ")
    $btnRun.X = 2
    $btnRun.Y = 5
    $btnRun.add_Clicked({
        [Terminal.Gui.MessageBox]::Query("WORKSPACE", "Tombol di panel Content berfungsi!", [string[]]@("OK")) | Out-Null
    })
    $contentPanel.Add($lblTitle, $btnRun)

    # [4. FOOTER]
    $footerPanel = [Terminal.Gui.FrameView]::new(" LOG STREAM & HOTKEYS ")
    $footerPanel.X = 0
    $footerPanel.Y = [Terminal.Gui.Pos]::Bottom($navPanel)
    $footerPanel.Width = [Terminal.Gui.Dim]::Fill()
    $footerPanel.Height = [Terminal.Gui.Dim]::Fill() 

    $lblLog = [Terminal.Gui.Label]::new("INFO: Menunggu perintah eksekusi...")
    $lblLog.X = 1
    $lblLog.Y = 0

    $lblHotkeys = [Terminal.Gui.Label]::new("HOTKEYS: [Tab] Panel  |  [Click] Menu")
    $lblHotkeys.X = 1
    $lblHotkeys.Y = 1

    $btnExit = [Terminal.Gui.Button]::new("EXIT COCKPIT")
    $btnExit.X = [Terminal.Gui.Pos]::Right($footerPanel) - 28
    $btnExit.Y = 1
    $btnExit.add_Clicked({
        $jawaban = [Terminal.Gui.MessageBox]::Query("PERINGATAN", "Apakah Anda yakin ingin keluar dari Rasamala Cockpit?", [string[]]@("Batal", "Ya, Keluar"))
        
        if ($jawaban -eq 1) {
            # Buka gembok pengaman karena dikonfirmasi dari tombol
            $script:isSafeToExit = $true
            [Terminal.Gui.Application]::RequestStop()
        }
    })
    $footerPanel.Add($lblLog, $lblHotkeys, $btnExit)

    # ---------------------------------------------------------
    # RENDER SEMUA PANEL
    # ---------------------------------------------------------
    $win.Add($headerPanel, $navPanel, $contentPanel, $footerPanel)
    $top.Add($win)

    [Terminal.Gui.Application]::Run()
    [Terminal.Gui.Application]::Shutdown()
}