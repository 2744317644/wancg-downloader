param(
    [switch]$Publish,
    [string]$Configuration = "Release",
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root "WnacgDownloader\WnacgDownloader.csproj"

$dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue)?.Source
if (-not $dotnet) {
    $candidates = @(
        (Join-Path $env:USERPROFILE ".dotnet\dotnet.exe"),
        "E:\Tools\dotnet8\dotnet.exe",
        "C:\Program Files\dotnet\dotnet.exe"
    )
    $dotnet = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $dotnet) {
    throw "找不到 dotnet。请先安装 .NET 8 SDK：https://dotnet.microsoft.com/download/dotnet/8.0"
}

if (-not $Publish) {
    & $dotnet build $project -c $Configuration -p:Platform=x64
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $root "dist\WnacgDownloader-win-x64"
}
Remove-Item $Output -Recurse -Force -ErrorAction SilentlyContinue
& $dotnet publish $project `
    -c $Configuration -r win-x64 --self-contained true `
    -p:Platform=x64 `
    -p:WindowsPackageType=None `
    -p:WindowsAppSDKSelfContained=true `
    -p:PublishTrimmed=false `
    -p:DebugType=None -p:DebugSymbols=false `
    -o $Output
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$zip = "$Output.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Resolve-Path $Output).Path,
    $zip,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $true
)
Write-Host "发布完成：$Output"
Write-Host "压缩包：$zip"
