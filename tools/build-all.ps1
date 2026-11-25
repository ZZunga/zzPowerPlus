<#  build-all.ps1 - zzPowerPlus 를 전 기기용으로 빌드. SDK 는 설치된 최신 버전을 자동으로 찾는다. #>
param(
    [string]$Sdk = "",
    [string]$Key = "$env:USERPROFILE\.Garmin\ConnectIQ\developer_key",
    [int]$TypeCheck = 3
)
$ErrorActionPreference = "Stop"

# SDK 를 지정하지 않으면 설치된 것 중 가장 최신 버전을 쓴다 (9.3.0 올려도 손 볼 필요 없음)
if ($Sdk -eq "") {
    $root = "$env:APPDATA\Garmin\ConnectIQ\Sdks"
    $Sdk = (Get-ChildItem $root -Directory |
            Where-Object { $_.Name -match '^connectiq-sdk-win-(\d+\.\d+\.\d+)' } |
            Sort-Object { [version]($_.Name -replace '^connectiq-sdk-win-(\d+\.\d+\.\d+).*$','$1') } |
            Select-Object -Last 1).FullName
    if (-not $Sdk) { throw "SDK 를 찾을 수 없습니다: $root" }
}
Write-Host "SDK: $Sdk" -ForegroundColor DarkGray

$devices = "edge540","edge550","edge840","edge850","edge1040","edge1050","edge1060"
$mc = Join-Path $Sdk "bin\monkeyc.bat"
New-Item -ItemType Directory -Force -Path bin | Out-Null

foreach ($d in $devices) {
    Write-Host "=== $d ===" -ForegroundColor Cyan
    & $mc -f monkey.jungle -d $d -o "bin/zzPowerPlus-$d.prg" -y $Key -w -l $TypeCheck
}
Write-Host "done." -ForegroundColor Green
