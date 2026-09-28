# Command line for MycoMap Atlas (PowerShell).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:ATLAS_ROOT = $here
& Rscript (Join-Path $here "inst\run.R") @args
exit $LASTEXITCODE
