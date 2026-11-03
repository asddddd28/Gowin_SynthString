param([string]$VivadoBin='D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    $env:PYTHONIOENCODING='utf-8'
    foreach ($script in @('dx7_validation.py','voice_engine_model.py','fm_interpolation_validation.py','preset_vectors.py','lfo_engine_vectors.py')) {
        python "model/$script"
        if ($LASTEXITCODE -ne 0) { throw "Python failed: $script" }
    }
    $suites=@('dx_envelope','dx_operator','fm1_engine','fm_operator','fm_interpolation','voice_engine','voice_presets','lfo_engine')
    $testSources=$suites | ForEach-Object { "sim/tb_$_.v" }
    & "$VivadoBin/xvlog.bat" -f sources.f @testSources -log reports/dx-xvlog.log *> reports/dx-compile.log
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    foreach ($name in $suites) {
        & "$VivadoBin/xelab.bat" "tb_$name" -s "dx_$name" -log "reports/dx-$name-xelab.log" *> "reports/dx-$name-elaborate.log"
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $name" }
        & "$VivadoBin/xsim.bat" "dx_$name" -runall -log "reports/dx-$name-xsim.log" *> "reports/dx-$name-run.log"
        $content=Get-Content -LiteralPath "reports/dx-$name-xsim.log" -Raw
        if ($LASTEXITCODE -ne 0 -or $content -notmatch 'PASS ' -or $content -match 'Fatal:|FATAL|ERROR:') { throw "xsim failed: $name" }
        Select-String -LiteralPath "reports/dx-$name-xsim.log" -Pattern 'PASS '
    }
} finally { Pop-Location }
