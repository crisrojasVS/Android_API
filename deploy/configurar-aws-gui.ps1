param(
  [string]$Region = 'us-east-1'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$artifactsDir = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null
$logPath = Join-Path $artifactsDir 'aws-config-gui.log'

function Write-Log {
  param([string]$Message)
  Add-Content -Path $logPath -Value "[$(Get-Date -Format 'o')] $Message"
}

Write-Log 'Inicio de configuracion GUI'

function Show-Message {
  param(
    [string]$Text,
    [string]$Title = 'Configuracion de AWS',
    [string]$Icon = 'Information'
  )

  [System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', $Icon) | Out-Null
}

try {
  Write-Log 'Abriendo dialogo de credenciales'
  $cred = Get-Credential `
    -Message 'AWS CLI: escribe el Access Key ID como usuario y el Secret Access Key como contrasena.'
  Write-Log 'Dialogo cerrado'

  if ($null -eq $cred) {
    Write-Log 'El usuario cancelo el dialogo'
    Show-Message 'Configuracion cancelada.' 'AWS' 'Warning'
    exit 1
  }

  $accessKey = $cred.UserName.Trim()
  $secretKey = $cred.GetNetworkCredential().Password.Trim()

  if ([string]::IsNullOrWhiteSpace($accessKey) -or [string]::IsNullOrWhiteSpace($secretKey)) {
    Show-Message 'El Access Key ID y el Secret Access Key no pueden estar vacios.' 'AWS' 'Error'
    exit 1
  }

  $awsDir = Join-Path $env:USERPROFILE '.aws'
  New-Item -ItemType Directory -Force -Path $awsDir | Out-Null

  $credentialsPath = Join-Path $awsDir 'credentials'
  $configPath = Join-Path $awsDir 'config'

  @"
[default]
aws_access_key_id = $accessKey
aws_secret_access_key = $secretKey
"@ | Set-Content -Path $credentialsPath -Encoding ascii

  @"
[default]
region = $Region
output = json
"@ | Set-Content -Path $configPath -Encoding ascii

  $currentUser = "$env:USERDOMAIN\$env:USERNAME"
  & icacls.exe $credentialsPath /inheritance:r | Out-Null
  & icacls.exe $credentialsPath /grant:r "${currentUser}:(R,W)" | Out-Null
  & icacls.exe $configPath /inheritance:r | Out-Null
  & icacls.exe $configPath /grant:r "${currentUser}:(R,W)" | Out-Null

  $identityJson = & python -m awscli sts get-caller-identity --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw ($identityJson -join "`n")
  }

  $identity = $identityJson | ConvertFrom-Json
  @{
    account      = $identity.Account
    arn          = $identity.Arn
    region       = $Region
    configuredAt = (Get-Date).ToString('o')
  } | ConvertTo-Json | Set-Content -Path (Join-Path $artifactsDir 'aws-config-ok.json') -Encoding UTF8

  Write-Log "Configuracion correcta para $($identity.Arn)"
  Show-Message "AWS configurado correctamente.`n`nCuenta: $($identity.Account)`nUsuario: $($identity.Arn)`nRegion: $Region" 'AWS listo' 'Information'
} catch {
  Write-Log ("ERROR: " + $_.Exception.ToString())
  Show-Message "No se pudo configurar AWS:`n`n$($_.Exception.Message)" 'Error de AWS' 'Error'
  exit 1
}
