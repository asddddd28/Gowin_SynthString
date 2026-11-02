param([string]$VivadoBin='D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference='Stop'
& "$PSScriptRoot/run_dx7_validation.ps1" -VivadoBin $VivadoBin
& "$PSScriptRoot/run_fx_validation.ps1" -VivadoBin $VivadoBin
