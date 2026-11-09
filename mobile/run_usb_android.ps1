param(
  [int]$ApiPort = 3001,
  [string]$DeviceSerial
)

$ErrorActionPreference = 'Stop'
$appId = 'com.houseofsauces.house_of_sauces'
$apiBaseUrl = "http://127.0.0.1:$ApiPort/api"

$flutter = Get-Command flutter.bat -ErrorAction SilentlyContinue
if ($flutter) {
  $flutterPath = $flutter.Source
} else {
  $sdkPath = $env:FLUTTER_HOME
  if (-not $sdkPath -and (Test-Path 'H:\Softwares\FlutterSDK\bin\flutter.bat')) {
    $sdkPath = 'H:\Softwares\FlutterSDK'
  }
  if (-not $sdkPath -and (Test-Path 'H:\Softwares\FLutter SDK\flutter\bin\flutter.bat')) {
    $sdkPath = 'H:\Softwares\FLutter SDK\flutter'
  }
  if (-not $sdkPath) {
    throw 'Flutter was not found. Add flutter.bat to PATH or set FLUTTER_HOME.'
  }
  $flutterPath = Join-Path $sdkPath 'bin\flutter.bat'
}

$adb = Get-Command adb.exe -ErrorAction SilentlyContinue
if ($adb) {
  $adbPath = $adb.Source
} elseif ($env:ANDROID_HOME -and (Test-Path (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'))) {
  $adbPath = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
} elseif ($env:ANDROID_SDK_ROOT -and (Test-Path (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'))) {
  $adbPath = Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
} else {
  throw 'Android Debug Bridge was not found. Set ANDROID_HOME or add adb.exe to PATH.'
}

$androidSdk = $env:ANDROID_HOME
if (-not $androidSdk) { $androidSdk = $env:ANDROID_SDK_ROOT }
if (-not $androidSdk) {
  $androidSdk = Split-Path (Split-Path $adbPath -Parent) -Parent
}
if (-not (Test-Path $androidSdk)) {
  throw "Android SDK directory not found: $androidSdk"
}
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk

if (-not $env:JAVA_HOME -and (Test-Path 'C:\Program Files\Android\Android Studio\jbr')) {
  $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
}

if (-not (Test-Path $flutterPath)) {
  throw "Flutter executable not found: $flutterPath"
}

$healthUri = "http://127.0.0.1:$ApiPort/health"
try {
  $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 5
} catch {
  throw "The House of Sauces API is not reachable at $healthUri. Start Docker Compose first and check API_PORT in .env."
}
if ($health.status -ne 'ok') {
  throw "The API at $healthUri did not report a healthy status."
}

$deviceOutput = & $adbPath devices
if ($LASTEXITCODE -ne 0) {
  throw 'Could not query Android devices with adb.'
}
$devices = @(
  $deviceOutput | Select-Object -Skip 1 | ForEach-Object {
    $parts = "$_".Trim() -split '\s+'
    if ($parts.Length -ge 2 -and $parts[1] -eq 'device') { $parts[0] }
  } | Where-Object { $_ }
)

if ($DeviceSerial) {
  if ($devices -notcontains $DeviceSerial) {
    throw "Android device '$DeviceSerial' is not connected or has not authorized USB debugging."
  }
} elseif ($devices.Count -eq 1) {
  $DeviceSerial = $devices[0]
} elseif ($devices.Count -eq 0) {
  throw 'No authorized Android phone is connected. Connect it with USB, enable USB debugging, and accept its authorization prompt.'
} else {
  throw 'More than one Android device is connected. Run this script again with -DeviceSerial <serial>.'
}

& $adbPath -s $DeviceSerial reverse "tcp:$ApiPort" "tcp:$ApiPort"
if ($LASTEXITCODE -ne 0) {
  throw 'Could not create the USB reverse tunnel to the local API.'
}

Push-Location $PSScriptRoot
try {
  & $flutterPath build apk --debug "--dart-define=API_BASE_URL=$apiBaseUrl"
  if ($LASTEXITCODE -ne 0) {
    throw 'Flutter could not build the USB-connected Android app.'
  }

  $apkPath = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-debug.apk'
  & $adbPath -s $DeviceSerial install -r $apkPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not install the debug APK on the connected phone.'
  }

  & $adbPath -s $DeviceSerial shell monkey -p $appId 1
  if ($LASTEXITCODE -ne 0) {
    throw 'The app was installed but could not be launched.'
  }
} finally {
  Pop-Location
}

Write-Host "House of Sauces is running on device $DeviceSerial."
Write-Host "USB API tunnel: phone 127.0.0.1:$ApiPort -> this computer 127.0.0.1:$ApiPort"
Write-Host 'Keep Docker Desktop and this computer on while using the app. No internet connection is needed.'
