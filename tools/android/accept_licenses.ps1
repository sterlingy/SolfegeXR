# Shows Google's Android SDK licenses so YOU can read and accept them (type y).
# Run in PowerShell:  & 'Y:\Projects - INTERNAL\SolfegeXR\tools\android\accept_licenses.ps1'
# Uses this machine's JDK/SDK when JAVA_HOME / ANDROID_HOME are set, otherwise
# the copy of the SDK tools on the shared drive, so any Windows user can run it.
$base = 'Y:\Projects - INTERNAL\SolfegeXR\thirdparty\android-bootstrap'
if (-not ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe')))) {
    $env:JAVA_HOME = Join-Path $base 'jdk'
}
if ($env:ANDROID_HOME -and (Test-Path (Join-Path $env:ANDROID_HOME 'cmdline-tools'))) {
    $sdk = $env:ANDROID_HOME
} else {
    $sdk = Join-Path $base 'sdk'
}
Write-Host ''
Write-Host 'Android SDK licenses: read each one, then type y and press Enter to accept.' -ForegroundColor Cyan
Write-Host ''
& (Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat') "--sdk_root=$sdk" --licenses
Write-Host ''
Write-Host 'Done. You can close this window.' -ForegroundColor Green
