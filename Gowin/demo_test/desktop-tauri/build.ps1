$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
npm ci
if ($LASTEXITCODE) { throw 'npm ci failed' }
npm run tauri -- build --no-bundle -- --locked
if ($LASTEXITCODE) { throw 'Tauri build failed' }
New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'release') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src-tauri/target/release/tang-hardware-lab.exe') -Destination (Join-Path $PSScriptRoot 'release/TangHardwareLab.exe') -Force
Write-Host 'Built release/TangHardwareLab.exe'
