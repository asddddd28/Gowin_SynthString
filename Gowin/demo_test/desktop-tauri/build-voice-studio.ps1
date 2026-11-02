param([string]$Output='../../demo1/voice-system/app')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    python ../../demo1/voice-engine/model/export_app_bank.py
    if($LASTEXITCODE -ne 0){throw 'Bank export failed'}
    npm run build
    if($LASTEXITCODE -ne 0){throw 'Frontend build failed'}
    cargo build --release --locked --features custom-protocol --manifest-path src-tauri/Cargo.toml --bin synthstring-voice-studio --bin voice-probe
    if($LASTEXITCODE -ne 0){throw 'Native build failed'}
    New-Item -ItemType Directory -Force -Path $Output | Out-Null
    Copy-Item src-tauri/target/release/synthstring-voice-studio.exe "$Output/SynthStringVoiceStudio.exe"
    Copy-Item src-tauri/target/release/voice-probe.exe "$Output/voice-probe.exe"
    Copy-Item ../../demo1/voice-engine/assets/fm1/UPSTREAM_NOTICES.md "$Output/FM1_NOTICES.md"
    Copy-Item ../../demo1/voice-engine/assets/fm1/DSP_NOTICE.txt "$Output/DSP_NOTICE.txt"
    Copy-Item VOICE_STUDIO.md "$Output/README.md"
} finally {Pop-Location}
