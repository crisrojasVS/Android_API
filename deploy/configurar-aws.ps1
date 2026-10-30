param(
  [string]$Region = 'us-east-1'
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=== Configuracion de AWS CLI ===' -ForegroundColor Cyan
Write-Host 'Necesitas el Access Key ID y el Secret Access Key de un usuario IAM.'
Write-Host 'Las credenciales se guardan en tu perfil de Windows (~/.aws), no en este proyecto.'
Write-Host ''

& python -m awscli configure set region $Region
& python -m awscli configure set output json

Write-Host "Region por defecto: $Region" -ForegroundColor DarkGray
Write-Host 'Introduce el Access Key ID, el Secret Access Key y presiona Enter en las demas preguntas.' -ForegroundColor Yellow
Write-Host ''

& python -m awscli configure

Write-Host ''
Write-Host 'Verificando identidad con AWS...' -ForegroundColor Cyan
$identityJson = & python -m awscli sts get-caller-identity --output json 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host $identityJson -ForegroundColor Red
  Write-Host ''
  Write-Host 'No se pudo verificar la identidad. Revisa las credenciales.' -ForegroundColor Red
} else {
  $identity = $identityJson | ConvertFrom-Json
  Write-Host "Cuenta:   $($identity.Account)" -ForegroundColor Green
  Write-Host "Usuario:  $($identity.Arn)" -ForegroundColor Green
  Write-Host ''
  Write-Host 'Configuracion terminada. Ya puedes volver a OpenCode.' -ForegroundColor Green
}

Write-Host ''
Read-Host 'Presiona Enter para cerrar esta ventana'
