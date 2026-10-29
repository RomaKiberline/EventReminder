# Keep start_backend.ps1 running in another terminal. Enable USB debugging.
$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (!(Test-Path $adb)) { throw 'ADB is missing: install Android SDK Platform Tools' }
& $adb reverse tcp:8000 tcp:8000
Set-Location (Join-Path $PSScriptRoot '..\flutter')
flutter pub get
flutter devices
Write-Host 'Change device ID below if flutter devices lists a different phone.'
flutter run -d 469fc43b '--dart-define=EVENT_REMINDER_API_URL=http://127.0.0.1:8000'
