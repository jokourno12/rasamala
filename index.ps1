[CmdletBinding()]
param(
    [switch]$OperatingSystem,
    [switch]$CheckingUpdateSystem,
    [switch]$CheckingDiskEncryption,
    [switch]$CheckingFirewall,
    [switch]$CheckingNetworkPorts,
    [switch]$CheckingRemoteSession,
    [switch]$CheckingOutboundConnection,

    [switch]$EndpointMetric,
    [switch]$AqlMonitoring,
    [switch]$BrowserIsolation,
    [switch]$JavaScript,

    [switch]$F5Reset,

    [switch]$SlaInfo,

    # AQL Monitoring
    [ValidateSet(7, 14, 28, 42)]
    [int]$InitialInterval = 7,

    #SLA Information
    [ValidateSet('All', 'Taspen', 'Pertamina')]
    [string]$Client = 'All',

    #Isolated Session
    [Parameter(Mandatory=$false)]
    [string]$TargetUrl = "about:blank"
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Helpers\SlaInfo.ps1
. $PSScriptRoot\Routes\Audit.ps1
. $PSScriptRoot\Routes\Operation.ps1
. $PSScriptRoot\Routes\Remediation.ps1

function showBanner {
    helperBanner
}

showBanner
# Audit
if ($OperatingSystem){
    routeOperatingSystem
}

if ($CheckingUpdateSystem){
    routeCheckingUpdateSystem
}

if ($CheckingDiskEncryption){
    routeCheckingDiskEncryption
}

if ($CheckingFirewall){
    routeCheckingFirewall
}

if ($CheckingNetworkPorts){
    routeCheckingNetworkPorts
}

if ($CheckingRemoteSession){
    routeCheckingRemoteSession
}

if ($CheckingOutboundConnection){
    routeCheckingOutboundConnection
}

# Operation
if ($EndpointMetric){
    routeEndpointMetric
}

if ($AqlMonitoring){
    routeAqlMonitoring
}

if ($BrowserIsolation){
    routeBrowserIsolation
}

if ($JavaScript){
    Write-Host "[Operation] Memeriksa Deno Runtime..." -ForegroundColor Cyan
    
    # 1. Cek & Install Deno (Logika yang sama seperti sebelumnya)
    if (-not (Get-Command deno -ErrorAction SilentlyContinue)) {
        Write-Host "[Operation] Deno tidak ditemukan. Memulai instalasi otomatis..." -ForegroundColor Yellow
        try {
            irm https://deno.land/install.ps1 | iex
            $denoBin = "$env:USERPROFILE\.deno\bin"
            if (Test-Path $denoBin) { $env:PATH = "$denoBin;$env:PATH" }
            Write-Host "✓ Deno berhasil dipasang!" -ForegroundColor Green
        } catch {
            Write-Host "✕ Gagal menginstal Deno." -ForegroundColor Red
            return
        }
    }

    # 2. Eksekusi file Deno.js menggunakan Deno
    $targetScript = "$PSScriptRoot\Helpers\Deno.js"
    
    if (Test-Path $targetScript) {
        Write-Host "[Operation] Mengeksekusi modul JavaScript..." -ForegroundColor Cyan
        
        # Eksekusi dilakukan di sini, bukan di dot-source atas
        deno run --allow-all $targetScript 
    } else {
        Write-Host "[-] Peringatan: File $targetScript tidak ditemukan." -ForegroundColor Yellow
    }
}

# Remediation
if ($F5Reset){
    routeF5Reset
}

# Information
if ($SlaInfo){
    helperSlaInfo -Client $Client
    exit
}