<#  export-iq.ps1 - 스토어 업로드용 .iq 패키지 (전 기기 포함, 릴리스 빌드)
    결과: bin/zzPowerPlus.iq.  SDK 는 설치된 최신 버전을 자동으로 찾는다.                #>
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

$mc = Join-Path $Sdk "bin\monkeyc.bat"
New-Item -ItemType Directory -Force -Path bin | Out-Null
& $mc -e -r -w -f monkey.jungle -o bin/zzPowerPlus.iq -y $Key -l $TypeCheck
Write-Host "-> bin/zzPowerPlus.iq" -ForegroundColor Green
