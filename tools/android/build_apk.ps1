# Builds the Android XR app (APK) with Godot + Gradle.
# Run in your own PowerShell window (Gradle can't run inside Claude's sandbox):
#   & 'Y:\Projects - INTERNAL\SolfegeXR\tools\android\build_apk.ps1'
# The first run downloads Gradle and Android libraries (a few minutes, needs internet).
# Output: Y:\Projects - INTERNAL\SolfegeXR\build\android\SolfegeXR.apk

$ErrorActionPreference = 'Stop'
$project = 'Y:\Projects - INTERNAL\SolfegeXR'
$base = Join-Path $project 'thirdparty\android-bootstrap'
$godot = 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe'

$env:JAVA_HOME = Join-Path $base 'jdk'
$env:ANDROID_HOME = Join-Path $base 'sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

# Point this Windows user's Godot editor settings at the shared JDK/SDK.
$settings = Join-Path $env:APPDATA 'Godot\editor_settings-4.7.tres'
if (Test-Path $settings) {
    $text = Get-Content $settings -Raw
    $jdk = $env:JAVA_HOME.Replace('\', '/')
    $sdk = $env:ANDROID_HOME.Replace('\', '/')
    $text = $text -replace '(?m)^export/android/java_sdk_path = ".*"$', "export/android/java_sdk_path = `"$jdk`""
    $text = $text -replace '(?m)^export/android/android_sdk_path = ".*"$', "export/android/android_sdk_path = `"$sdk`""
    Set-Content -Path $settings -Value $text -Encoding UTF8 -NoNewline
    Write-Host 'Godot editor settings now point at the shared JDK and Android SDK.' -ForegroundColor Cyan
} else {
    Write-Host 'No Godot editor settings for this user yet; using JAVA_HOME / ANDROID_HOME.' -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path (Join-Path $project 'build\android') | Out-Null
Write-Host ''
Write-Host 'Building the Android XR APK (first time: several minutes)...' -ForegroundColor Cyan
& $godot --headless --path $project --export-debug 'Android XR' 'build/android/SolfegeXR.apk' 2>&1 |
    Tee-Object -FilePath (Join-Path $project 'build\android\export.log') |
    Where-Object { $_ -match 'BUILD|FAIL|error:|What went wrong|Downloading|apk' }

$apk = Join-Path $project 'build\android\SolfegeXR.apk'
Write-Host ''
if (Test-Path $apk) {
    Write-Host ("Done: {0} ({1:N1} MB)" -f $apk, ((Get-Item $apk).Length / 1MB)) -ForegroundColor Green
} else {
    Write-Host 'The build did not produce an APK. The full log is in build\android\export.log; Claude can read it.' -ForegroundColor Red
}
