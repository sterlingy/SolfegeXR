# Shows Google's Android SDK licenses so YOU can read and accept them (type y).
# Run in PowerShell:  & 'Y:\Projects - INTERNAL\SolfegeXR\tools\android\accept_licenses.ps1'
# Uses a copy of the SDK tools on the shared drive, so any Windows user can run it.
$base = 'Y:\Projects - INTERNAL\SolfegeXR\thirdparty\android-bootstrap'
$env:JAVA_HOME = Join-Path $base 'jdk'
$sdk = Join-Path $base 'sdk'
Write-Host ''
Write-Host 'Android SDK licenses: read each one, then type y and press Enter to accept.' -ForegroundColor Cyan
Write-Host ''
& (Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat') "--sdk_root=$sdk" --licenses
Write-Host ''
Write-Host 'Done. You can close this window.' -ForegroundColor Green
