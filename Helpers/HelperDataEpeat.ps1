function etl{
    Write-Host "[*] Starts the ETL: Excel to LiteDB process..."
    
    $databasePath = "$PSScriptRoot\..\Database"
    $libPath = "$PSScriptRoot\Lib"
    $excelFile = "$databasePath\EPEAT_Export.xlsx"
    $dbFile = "$databasePath\sustainability.db"
    $liteDbDll = "$libPath\LiteDB.dll" 

    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host "[-] ImportExcel module not found. Starting installation..." -ForegroundColor Yellow
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
        Write-Host "[+] The ImportExcel module was installed successfully." -ForegroundColor Green
    }
    
    if (-not (Test-Path $liteDbDll)) {
        Write-Host "[-] LiteDB.dll library not found. Prepare environment..." -ForegroundColor Yellow
        
        if (-not (Test-Path $libPath)) {
            New-Item -Path $libPath -ItemType Directory -Force | Out-Null
        }

        $zipPath = "$libPath\litedb.zip"
        $extractPath = "$libPath\litedb_extracted"

        Write-Host "    -> Downloading the LiteDB package..."
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/LiteDB/5.0.17" -OutFile $zipPath

        Write-Host "    -> Extracting and copying DLL..."
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Copy-Item -Path "$extractPath\lib\netstandard2.0\LiteDB.dll" -Destination $liteDbDll -Force

        Remove-Item -Path $zipPath -Force
        Remove-Item -Path $extractPath -Recurse -Force

        Write-Host "[+] The LiteDB.dll library was successfully set up." -ForegroundColor Green
    }

    Write-Host "[*] Read data from $excelFile..."
    if (-not (Test-Path $excelFile)) {
        Write-Host "[X] Excel file not found: $excelFile" -ForegroundColor Red
        return
    }
    $excelData = Import-Excel -Path $excelFile

    Add-Type -Path $liteDbDll
    $db = New-Object LiteDB.LiteDatabase("Filename=$dbFile;Connection=shared")
    $collection = $db.GetCollection("epeat_products")
    
    $collection.DeleteAll() | Out-Null

    Write-Host "[*] Insert data into the database sustainability.db..."
    foreach ($row in $excelData) {
        $doc = New-Object LiteDB.BsonDocument
        
        $doc["product_name"] = [LiteDB.BsonValue]::new([string]$row.'Product Name')
    $doc["manufacturer"] = [LiteDB.BsonValue]::new([string]$row.Manufacturer)
    $doc["tier"]         = [LiteDB.BsonValue]::new([string]$row.'EPEAT Tier')
        
        $collection.Insert($doc) | Out-Null
    }

    $db.Dispose()

    if (Test-Path $excelFile) {
        Remove-Item -Path $excelFile -Force
        Write-Host "[+] The temporary Excel file ($excelFile) was successfully deleted." -ForegroundColor Gray
    }

    Write-Host "[+] ETL process completed. The EPEAT 1.0 sustainability.db database is ready to use!" -ForegroundColor Green
}

function helperDataEpeat{
    $today = Get-Date
    $existingFile = Get-ChildItem -Path "$PSScriptRoot\..\Database\sustainability.db" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | 
                    Select-Object -First 1

    if ((-not $existingFile) -or (($today - $existingFile.LastWriteTime).Days -ge 3)){
        $totalHits = 0

        try {
            Invoke-RestMethod -Uri "https://www.epeat.net/api/report/generate" -Method POST -ContentType "application/json" -Body '{"facets":{"status":["Active"]},"isAdvanced":false,"query":""}' -ErrorAction Stop
        } catch {
            $errorJson =$_.ErrorDetails.Message | ConvertFrom-Json
            $totalHits =$errorJson.ActualHits
        }

        if ($totalHits -gt 0) {
            Invoke-WebRequest -Uri "https://www.epeat.net/product-finder?menu[status]=Active" -SessionVariable session -UseBasicParsing | Out-Null

            $payload = '{"facets":{"status":["Active"]},"totalNumberOfResult":' + $totalHits + ',"isAdvanced":false,"query":""}'

            Invoke-WebRequest -Uri "https://www.epeat.net/api/report/generate" `
                -Method "POST" `
                -WebSession $session `
                -Headers @{
                    "accept"="*/*"
                    "origin"="https://www.epeat.net"
                    "referer"="https://www.epeat.net/product-finder"
                } `
                -ContentType "application/json" `
                -Body $payload `
                -OutFile "$PSScriptRoot\..\Database\EPEAT_Export.xlsx"

            etl
        }
    }
}