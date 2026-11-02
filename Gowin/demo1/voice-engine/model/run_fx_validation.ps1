param([string]$VivadoBin='D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference='Stop'
$workRoot=Split-Path -Parent $PSScriptRoot
Push-Location $workRoot
try {
    $env:PYTHONIOENCODING='utf-8'
    foreach ($script in @('fx_model.py','fx_testbench.py','fx_axi_testbench.py','check_fx_compiler.py')) {
        python "model/$script"
        if ($LASTEXITCODE -ne 0) { throw "Python failed: $script" }
    }
    $suites=@('fx_delay','fx_reverb','axi_fx','axi_voice_endpoint','axi_synth_engine','axi_lfo')
    $testSources=$suites | ForEach-Object { "sim/tb_$_.v" }
    & "$VivadoBin/xvlog.bat" -f sources.f @testSources *> reports/fx-final-xvlog.log
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    foreach ($name in $suites) {
        & "$VivadoBin/xelab.bat" "tb_$name" -s "fx_final_$name" *> "reports/fx-final-$name-xelab.log"
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $name" }
        & "$VivadoBin/xsim.bat" "fx_final_$name" -runall *> "reports/fx-final-$name-xsim.log"
        $content=Get-Content -LiteralPath "reports/fx-final-$name-xsim.log" -Raw
        if ($LASTEXITCODE -ne 0 -or $content -notmatch 'PASS ' -or $content -match 'Fatal:|FATAL|ERROR:') { throw "xsim failed: $name" }
        Select-String -LiteralPath "reports/fx-final-$name-xsim.log" -Pattern 'PASS '
    }
    python model/check_fx_capture.py
    if ($LASTEXITCODE -ne 0) { throw 'full-chain oracle failed' }
} finally { Pop-Location }
