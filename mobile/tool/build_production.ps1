param(
  [string]$ApiBaseUrl = $env:HOS_API_BASE_URL
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
  throw 'Set HOS_API_BASE_URL to the deployed HTTPS API URL, including /api.'
}

$apiUri = $null
if (-not [Uri]::TryCreate($ApiBaseUrl, [UriKind]::Absolute, [ref]$apiUri) -or
    $apiUri.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($apiUri.Host) -or
    -not $apiUri.AbsolutePath.TrimEnd('/').EndsWith('/api')) {
  throw 'HOS_API_BASE_URL must be an absolute HTTPS URL ending in /api.'
}

$androidDirectory = Join-Path $PSScriptRoot '..\android'
$signingProperties = Join-Path $androidDirectory 'key.properties'
if (-not (Test-Path -LiteralPath $signingProperties -PathType Leaf)) {
  throw 'Missing mobile/android/key.properties. Configure your private Play release keystore before building.'
}

$flutter = Get-Command flutter.bat -ErrorAction SilentlyContinue
if ($flutter) {
  $flutterPath = $flutter.Source
} elseif (Test-Path -LiteralPath 'D:\devtools\flutter\bin\flutter.bat') {
  $flutterPath = 'D:\devtools\flutter\bin\flutter.bat'
} else {
  throw 'Flutter was not found. Add flutter.bat to PATH and rerun this script.'
}

Push-Location (Join-Path $PSScriptRoot '..')
try {
  & $flutterPath build appbundle --release "--dart-define=API_BASE_URL=$ApiBaseUrl"
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter release bundle build failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

Write-Output 'Signed production bundle: mobile\build\app\outputs\bundle\release\app-release.aab'
