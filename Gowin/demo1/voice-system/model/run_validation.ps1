param([string]$VivadoBin='D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    $env:PYTHONIOENCODING='utf-8'
    foreach ($script in @('system_model.py','system_vectors.py','compact_delay_test.py','master_testbench.py')) {
        python "model/$script"
        if ($LASTEXITCODE -ne 0) { throw "Python failed: $script" }
    }
    $suites=@('synth_system','synth_master','compact_delay')
    $testSources=$suites | ForEach-Object { "sim/tb_$_.v" }
    & "$VivadoBin/xvlog.bat" -f sources.f @testSources -log reports/final-xvlog.log *> reports/final-compile.log
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    foreach ($name in $suites) {
        & "$VivadoBin/xelab.bat" "tb_$name" -s "final_$name" -log "reports/final-$name-xelab.log" *> "reports/final-$name-elaborate.log"
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $name" }
        & "$VivadoBin/xsim.bat" "final_$name" -runall -log "reports/final-$name-xsim.log" *> "reports/final-$name-run.log"
        $content=Get-Content -LiteralPath "reports/final-$name-xsim.log" -Raw
        if ($LASTEXITCODE -ne 0 -or $content -notmatch 'PASS ' -or $content -match 'Fatal:|FATAL|ERROR:') { throw "xsim failed: $name" }
        Select-String -LiteralPath "reports/final-$name-xsim.log" -Pattern 'PASS '
    }
} finally { Pop-Location }
