# Command line for MycoMap Atlas (PowerShell).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:ATLAS_ROOT = $here

# R's Windows installer does not add R to PATH, so fall back to the usual
# install location before giving up.
$rscript = (Get-Command Rscript -ErrorAction SilentlyContinue).Source
if (-not $rscript) {
  $candidate = Get-ChildItem "C:\Program Files\R\R-*\bin\Rscript.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
  if ($candidate) { $rscript = $candidate.FullName }
}
if (-not $rscript) {
  Write-Error "Rscript not found. Install R 4.x: https://cran.r-project.org/bin/windows/base/"
  exit 1
}

& $rscript (Join-Path $here "inst\run.R") @args
exit $LASTEXITCODE
