function etl{
    Write-Host "[*] Memulai proses ETL: Excel ke LiteDB..."
    
    $databasePath = "$PSScriptRoot\..\Database"
    $libPath = "$PSScriptRoot\Lib"
    $excelFile = "$databasePath\EPEAT_Export.xlsx"
    $dbFile = "$databasePath\sustainability.db"
    $liteDbDll = "$libPath\LiteDB.dll" 

    # --- 1. VALIDASI & INSTALASI MODUL ImportExcel ---
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host "[-] Modul ImportExcel tidak ditemukan. Memulai instalasi..." -ForegroundColor Yellow
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
        Write-Host "[+] Modul ImportExcel berhasil diinstal." -ForegroundColor Green
    }
    
    # --- 2. VALIDASI & UNDUH OTOMATIS LiteDB.dll ---
    if (-not (Test-Path $liteDbDll)) {
        Write-Host "[-] Pustaka LiteDB.dll tidak ditemukan. Menyiapkan environment..." -ForegroundColor Yellow
        
        # Buat folder Lib jika belum ada
        if (-not (Test-Path $libPath)) {
            New-Item -Path $libPath -ItemType Directory -Force | Out-Null
        }

        $zipPath = "$libPath\litedb.zip"
        $extractPath = "$libPath\litedb_extracted"

        # Unduh dari repositori NuGet resmi
        Write-Host "    -> Mengunduh package LiteDB..."
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/LiteDB/5.0.17" -OutFile $zipPath

        # Ekstrak file dan ambil versi netstandard2.0 (Paling cocok untuk PowerShell 7 / Cross-Platform)
        Write-Host "    -> Mengekstrak dan menyalin DLL..."
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Copy-Item -Path "$extractPath\lib\netstandard2.0\LiteDB.dll" -Destination $liteDbDll -Force

        # Bersihkan file sementara
        Remove-Item -Path $zipPath -Force
        Remove-Item -Path $extractPath -Recurse -Force

        Write-Host "[+] Pustaka LiteDB.dll berhasil disiapkan." -ForegroundColor Green
    }

    # --- 3. BACA DATA EXCEL ---
    Write-Host "[*] Membaca data dari $excelFile..."
    # Mengecek apakah file Excel benar-benar ada sebelum dibaca
    if (-not (Test-Path $excelFile)) {
        Write-Host "[X] File Excel tidak ditemukan: $excelFile" -ForegroundColor Red
        return
    }
    $excelData = Import-Excel -Path $excelFile

    # --- 4. MUAT LITEDB & KONEKSI ---
    Add-Type -Path $liteDbDll
    $db = New-Object LiteDB.LiteDatabase("Filename=$dbFile;Connection=shared")
    $collection = $db.GetCollection("epeat_products")
    
    $collection.DeleteAll() | Out-Null # Kosongkan data lama

    # --- 5. PROSES PEMETAAN & PENYISIPAN DATA ---
    Write-Host "[*] Menyisipkan data ke database sustainability.db..."
    foreach ($row in $excelData) {
        $doc = New-Object LiteDB.BsonDocument
        
        # Sesuaikan ini dengan nama kolom di Excel Anda
        $doc["product_name"] = [LiteDB.BsonValue]::new([string]$row.'Product Name')
    $doc["manufacturer"] = [LiteDB.BsonValue]::new([string]$row.Manufacturer)
    $doc["tier"]         = [LiteDB.BsonValue]::new([string]$row.'EPEAT Tier')
        
        $collection.Insert($doc) | Out-Null
    }

    $db.Dispose()

    if (Test-Path $excelFile) {
        Remove-Item -Path $excelFile -Force
        Write-Host "[+] File Excel sementara ($excelFile) berhasil dihapus." -ForegroundColor Gray
    }

    Write-Host "[+] Proses ETL selesai. Database EPEAT 1.0 sustainability.db siap digunakan!" -ForegroundColor Green
}

function helperDataEpeat{
    $today = Get-Date
    $existingFile = Get-ChildItem -Path "$PSScriptRoot\..\Database\sustainability.db" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | 
                    Select-Object -First 1

    if ((-not $existingFile) -or (($today -$existingFile.LastWriteTime).Days -ge 3)){
        Invoke-WebRequest -Uri "https://www.epeat.net/product-finder?menu[status]=Active" -SessionVariable session -UseBasicParsing | Out-Null

        Invoke-WebRequest -Uri "https://www.epeat.net/api/report/generate" `
            -Method "POST" `
            -WebSession $session `
            -Headers @{
                "accept"="*/*"
                "origin"="https://www.epeat.net"
                "referer"="https://www.epeat.net/product-finder"
            } `
            -ContentType "application/json" `
            -Body '{"facets":{"status":["Active"]},"totalNumberOfResult":41626,"isAdvanced":false,"query":""}' `
            -OutFile "$PSScriptRoot\..\Database\EPEAT_Export.xlsx"

        etl
    }
}