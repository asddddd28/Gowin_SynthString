param([string]$Python='', [string]$Destination='release_games')
$ErrorActionPreference='Stop'
$desktopRoot=$PSScriptRoot
if (-not $Python) {
    $localPython=Join-Path $desktopRoot '.venv\Scripts\python.exe'
    $existingPython=Join-Path $desktopRoot '..\..\demo1\desktop\.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $localPython) {$Python=$localPython}
    elseif (Test-Path -LiteralPath $existingPython) {$Python=$existingPython}
    else {$Python='python'}
}
Push-Location $desktopRoot
try {
    & $Python -m unittest discover -s . -p 'test_*.py' -v
    if ($LASTEXITCODE -ne 0) {throw 'Tests failed'}
    & $Python -m PyInstaller --noconfirm --windowed --onedir --name TangKeyboardLab `
      --distpath (Join-Path $desktopRoot $Destination) --workpath (Join-Path $desktopRoot 'build_games') `
      --add-data 'measured_profile.json;.' app.py
    if ($LASTEXITCODE -ne 0) {throw 'Packaging failed'}
    Copy-Item -LiteralPath (Join-Path $desktopRoot 'README.md') -Destination (Join-Path $desktopRoot "$Destination\TangKeyboardLab\README.md") -Force
} finally {Pop-Location}
