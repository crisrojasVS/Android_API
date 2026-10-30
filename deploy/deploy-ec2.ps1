param(
  [string]$Region,
  [string]$InstanceType = 't3.micro',
  [string]$KeyName = 'agenda-api-key',
  [string]$SecurityGroupName = 'agenda-api-sg',
  [string]$TagName = 'api-agenda',
  [string]$EipTag = 'api-agenda-ip'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$env:AWS_PAGER = ''

function Invoke-Aws {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

  $output = & python -m awscli @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw ("AWS CLI fallo: " + ($output -join "`n"))
  }

  return (($output -join "`n").Trim())
}

function Invoke-AwsOptional {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

  $output = & python -m awscli @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  return (($output -join "`n").Trim())
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Object
  )

  $json = ConvertTo-Json -InputObject $Object -Depth 8 -Compress
  [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Get-FileUrl {
  param([string]$Path)

  return 'file://' + ($Path -replace '\\', '/')
}

function Test-Ssh {
  param(
    [string]$PublicIp,
    [string]$KeyPath
  )

  & ssh.exe -i $KeyPath `
    -o StrictHostKeyChecking=no `
    -o UserKnownHostsFile=NUL `
    -o ConnectTimeout=5 `
    -o BatchMode=yes `
    "ubuntu@$PublicIp" "echo ready" 2>$null | Out-Null

  return ($LASTEXITCODE -eq 0)
}

Write-Host ''
Write-Host '=== Despliegue de la API de Agenda en AWS EC2 ===' -ForegroundColor Cyan

Write-Host '==> Verificando AWS CLI...'
try {
  $identityRaw = Invoke-Aws sts get-caller-identity --output json
  $identity = $identityRaw | ConvertFrom-Json
} catch {
  Write-Host ''
  Write-Host 'No hay credenciales de AWS configuradas o no son validas.' -ForegroundColor Red
  Write-Host 'Ejecuta primero:' -ForegroundColor Yellow
  Write-Host '  powershell -ExecutionPolicy Bypass -File .\deploy\configurar-aws.ps1' -ForegroundColor Yellow
  throw
}

Write-Host "Cuenta AWS: $($identity.Account)" -ForegroundColor Green
Write-Host "Usuario:    $($identity.Arn)" -ForegroundColor Green

if (-not $Region) {
  $Region = Invoke-Aws configure get region
  if ([string]::IsNullOrWhiteSpace($Region)) {
    $Region = 'us-east-1'
  }
}
$env:AWS_DEFAULT_REGION = $Region
Write-Host "Region:     $Region" -ForegroundColor Green
Write-Host "Instancia:  $InstanceType" -ForegroundColor Green

Write-Host '==> Buscando una instancia existente...'
$existingRaw = Invoke-Aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=$TagName" "Name=instance-state-name,Values=pending,running,stopped" `
  --query 'Reservations[].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIp:PublicIpAddress,KeyName:KeyName}' `
  --output json

$existing = @($existingRaw | ConvertFrom-Json) | Where-Object { $_ -and $_.InstanceId } | Select-Object -First 1
$instanceId = $null
$publicIp = $null

if ($existing) {
  $instanceId = $existing.InstanceId
  $KeyName = $existing.KeyName
  Write-Host "Se reutilizara la instancia $instanceId (estado: $($existing.State))." -ForegroundColor Yellow

  if ($existing.State -eq 'stopped') {
    Write-Host '==> Iniciando instancia detenida...'
    Invoke-Aws ec2 start-instances --instance-ids $instanceId | Out-Null
  }

  Invoke-Aws ec2 wait instance-running --instance-ids $instanceId
  Invoke-Aws ec2 wait instance-status-ok --instance-ids $instanceId
} else {
  Write-Host 'No hay instancia previa; se creara una nueva.'
}

$keyPath = Join-Path $env:USERPROFILE ".ssh\$KeyName.pem"

if (-not (Test-Path $keyPath)) {
  Write-Host "==> Creando llave SSH $KeyName..."
  $keyExists = Invoke-AwsOptional ec2 describe-key-pairs --key-names $KeyName --output text
  if ($null -ne $keyExists -and $keyExists -ne '') {
    throw "La llave $KeyName existe en AWS pero no el archivo $keyPath. Elimina la llave en AWS o coloca el .pem en esa ruta antes de continuar."
  }

  $material = Invoke-Aws ec2 create-key-pair --key-name $KeyName --query KeyMaterial --output text
  $material = $material -replace "`r`n", "`n"
  New-Item -ItemType Directory -Force -Path (Split-Path $keyPath) | Out-Null
  [IO.File]::WriteAllText($keyPath, $material + "`n", [Text.UTF8Encoding]::new($false))
}

Write-Host "==> Ajustando permisos de la llave SSH..."
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
& icacls.exe $keyPath /inheritance:r | Out-Null
& icacls.exe $keyPath /grant:r "${currentUser}:(R)" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "No se pudieron ajustar los permisos de $keyPath"
}

Write-Host '==> Preparando Security Group...'
$vpcId = Invoke-Aws ec2 describe-vpcs --filters 'Name=isDefault,Values=true' --query 'Vpcs[0].VpcId' --output text
if ([string]::IsNullOrWhiteSpace($vpcId) -or $vpcId -eq 'None') {
  throw 'La cuenta no tiene una VPC por defecto. Crea una VPC o indica una subred manualmente.'
}

$sgId = Invoke-AwsOptional ec2 describe-security-groups `
  --filters "Name=group-name,Values=$SecurityGroupName" "Name=vpc-id,Values=$vpcId" `
  --query 'SecurityGroups[0].GroupId' --output text

if ($null -eq $sgId -or [string]::IsNullOrWhiteSpace($sgId) -or $sgId -eq 'None') {
  $sgId = Invoke-Aws ec2 create-security-group `
    --group-name $SecurityGroupName `
    --description 'API de Agenda: SSH y HTTP' `
    --vpc-id $vpcId `
    --query GroupId --output text
  Invoke-Aws ec2 create-tags --resources $sgId --tags "Key=Name,Value=$SecurityGroupName" | Out-Null
  Write-Host "Security Group creado: $sgId"
} else {
  Write-Host "Security Group existente: $sgId"
}

$myIp = (Invoke-RestMethod -Uri 'https://checkip.amazonaws.com' -TimeoutSec 15).Trim()
if ($myIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
  throw "No se pudo determinar una IP publica IPv4 valida (resultado: $myIp)."
}
Write-Host "IP publica para SSH: $myIp/32" -ForegroundColor DarkGray

$reglas = @(
  @{ IpProtocol = 'tcp'; FromPort = 22; ToPort = 22; IpRanges = @(@{ CidrIp = "$myIp/32"; Description = 'SSH administrador' }) },
  @{ IpProtocol = 'tcp'; FromPort = 80; ToPort = 80; IpRanges = @(@{ CidrIp = '0.0.0.0/0'; Description = 'HTTP API' }) }
)

foreach ($regla in $reglas) {
  $ruleFile = Join-Path $env:TEMP "agenda-sg-rule-$([guid]::NewGuid().ToString('N')).json"
  Write-JsonFile -Path $ruleFile -Object @{ GroupId = $sgId; IpPermissions = @($regla) }

  try {
    Invoke-Aws ec2 authorize-security-group-ingress --cli-input-json (Get-FileUrl $ruleFile) | Out-Null
  } catch {
    if ($_.Exception.Message -notmatch 'InvalidPermission.Duplicate') {
      throw
    }
  } finally {
    Remove-Item -Path $ruleFile -Force -ErrorAction SilentlyContinue
  }
}

if (-not $instanceId) {
  Write-Host '==> Obteniendo AMI de Ubuntu 24.04...'
  try {
    $amiId = Invoke-Aws ssm get-parameter `
      --name '/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id' `
      --query 'Parameter.Value' --output text
  } catch {
    Write-Host 'No se pudo usar SSM; buscando la AMI por nombre...' -ForegroundColor Yellow
    $amiId = Invoke-Aws ec2 describe-images `
      --owners '099720109477' `
      --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' 'Name=state,Values=available' `
      --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text
  }

  if ([string]::IsNullOrWhiteSpace($amiId) -or $amiId -eq 'None') {
    throw 'No se pudo encontrar una AMI de Ubuntu 24.04.'
  }

  $subnetId = Invoke-AwsOptional ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$vpcId" 'Name=default-for-az,Values=true' `
    --query 'Subnets[0].SubnetId' --output text

  if ($null -eq $subnetId -or [string]::IsNullOrWhiteSpace($subnetId) -or $subnetId -eq 'None') {
    $subnetId = Invoke-Aws ec2 describe-subnets `
      --filters "Name=vpc-id,Values=$vpcId" `
      --query 'Subnets[0].SubnetId' --output text
  }

  if ([string]::IsNullOrWhiteSpace($subnetId) -or $subnetId -eq 'None') {
    throw 'No se encontro una subred en la VPC por defecto.'
  }

  $rootDevice = Invoke-Aws ec2 describe-images --image-ids $amiId --query 'Images[0].RootDeviceName' --output text
  $runConfig = @{
    ImageId                  = $amiId
    InstanceType             = $InstanceType
    KeyName                  = $KeyName
    SecurityGroupIds         = @($sgId)
    SubnetId                 = $subnetId
    AssociatePublicIpAddress = $true
    BlockDeviceMappings      = @(@{
        DeviceName = $rootDevice
        Ebs        = @{ VolumeSize = 20; VolumeType = 'gp3'; DeleteOnTermination = $true }
      })
    TagSpecifications        = @(@{
        ResourceType = 'instance'
        Tags         = @(
          @{ Key = 'Name'; Value = $TagName },
          @{ Key = 'Project'; Value = 'api-agenda' }
        )
      })
    MetadataOptions          = @{ HttpTokens = 'required'; HttpEndpoint = 'enabled' }
  }

  $runFile = Join-Path $env:TEMP "agenda-run-instances-$([guid]::NewGuid().ToString('N')).json"
  Write-JsonFile -Path $runFile -Object $runConfig

  Write-Host "==> Creando instancia $InstanceType..."
  try {
    $instanceId = Invoke-Aws ec2 run-instances `
      --cli-input-json (Get-FileUrl $runFile) `
      --query 'Instances[0].InstanceId' --output text
  } finally {
    Remove-Item -Path $runFile -Force -ErrorAction SilentlyContinue
  }

  Write-Host "Instancia creada: $instanceId" -ForegroundColor Green
  Invoke-Aws ec2 wait instance-running --instance-ids $instanceId
  Invoke-Aws ec2 wait instance-status-ok --instance-ids $instanceId
}

Write-Host '==> Asociando Elastic IP...'
$allocationId = Invoke-AwsOptional ec2 describe-addresses `
  --filters "Name=tag:Name,Values=$EipTag" `
  --query 'Addresses[0].AllocationId' --output text

if ($null -eq $allocationId -or [string]::IsNullOrWhiteSpace($allocationId) -or $allocationId -eq 'None') {
  $allocationId = Invoke-Aws ec2 allocate-address --domain vpc --query AllocationId --output text
  Invoke-Aws ec2 create-tags --resources $allocationId --tags "Key=Name,Value=$EipTag" | Out-Null
}

try {
  Invoke-Aws ec2 associate-address --instance-id $instanceId --allocation-id $allocationId | Out-Null
} catch {
  if ($_.Exception.Message -notmatch 'already associated') {
    throw
  }
}

$publicIp = Invoke-Aws ec2 describe-addresses --allocation-ids $allocationId --query 'Addresses[0].PublicIp' --output text
if ([string]::IsNullOrWhiteSpace($publicIp) -or $publicIp -eq 'None') {
  throw 'No se pudo obtener la IP publica de la instancia.'
}
Write-Host "IP publica: $publicIp" -ForegroundColor Green

Write-Host '==> Esperando a que SSH este disponible...'
$sshReady = $false
for ($i = 1; $i -le 60; $i++) {
  if (Test-Ssh -PublicIp $publicIp -KeyPath $keyPath) {
    $sshReady = $true
    break
  }
  Start-Sleep -Seconds 5
}

if (-not $sshReady) {
  throw "SSH no respondio en $publicIp. Revisa el Security Group y que tu IP publica sea $myIp."
}
Write-Host 'SSH disponible.' -ForegroundColor Green

Write-Host '==> Empaquetando la API...'
$staging = Join-Path $env:TEMP "agenda-api-staging-$([guid]::NewGuid().ToString('N'))"
$bundle = Join-Path $env:TEMP "api-agenda-$([guid]::NewGuid().ToString('N')).tar.gz"
New-Item -ItemType Directory -Path $staging | Out-Null

try {
  Copy-Item -Path (Join-Path $ProjectRoot 'src') -Destination $staging -Recurse
  Copy-Item -Path (Join-Path $ProjectRoot 'database') -Destination $staging -Recurse
  Copy-Item -Path (Join-Path $ProjectRoot 'scripts') -Destination $staging -Recurse
  Copy-Item -Path (Join-Path $ProjectRoot 'package.json') -Destination $staging
  Copy-Item -Path (Join-Path $ProjectRoot 'package-lock.json') -Destination $staging
  Copy-Item -Path (Join-Path $ProjectRoot 'README.md') -Destination $staging

  & tar.exe -czf $bundle -C $staging .
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo crear el paquete tar.gz.'
  }
} finally {
  Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host '==> Subiendo archivos a la instancia...'
& scp.exe -i $keyPath `
  -o StrictHostKeyChecking=no `
  -o UserKnownHostsFile=NUL `
  $bundle "ubuntu@${publicIp}:/home/ubuntu/api-agenda.tar.gz"
if ($LASTEXITCODE -ne 0) { throw 'Fallo la subida del paquete de la API.' }

& scp.exe -i $keyPath `
  -o StrictHostKeyChecking=no `
  -o UserKnownHostsFile=NUL `
  (Join-Path $PSScriptRoot 'ec2-bootstrap.sh') "ubuntu@${publicIp}:/home/ubuntu/ec2-bootstrap.sh"
if ($LASTEXITCODE -ne 0) { throw 'Fallo la subida del script de instalacion.' }

Write-Host ''
Write-Host '==> Instalando Node, MySQL, Nginx y la API en la instancia...' -ForegroundColor Cyan
Write-Host 'Esto puede tardar varios minutos.' -ForegroundColor Yellow
Write-Host ''

& ssh.exe -i $keyPath `
  -o StrictHostKeyChecking=no `
  -o UserKnownHostsFile=NUL `
  "ubuntu@$publicIp" "chmod +x /home/ubuntu/ec2-bootstrap.sh && sudo bash /home/ubuntu/ec2-bootstrap.sh"
if ($LASTEXITCODE -ne 0) { throw 'El script de instalacion fallo. Revisa la salida anterior.' }

Remove-Item -Path $bundle -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '==> Probando la API por HTTP publico...' -ForegroundColor Cyan
$health = $null
for ($i = 1; $i -le 30; $i++) {
  try {
    $health = Invoke-RestMethod -Uri "http://$publicIp/health" -TimeoutSec 10
    break
  } catch {
    Start-Sleep -Seconds 2
  }
}

if ($null -eq $health) {
  throw "La API no respondio en http://$publicIp/health"
}

Write-Host "GET /health -> $($health.status), base de datos: $($health.database)" -ForegroundColor Green

$demoTitulo = "DEPLOY-API $(Get-Date -Format 'yyyyMMddHHmmss')"
$demoBody = @{
  titulo      = $demoTitulo
  tipo        = 'cita'
  fecha       = '2031-02-01'
  hora        = '10:30'
  descripcion = 'Prueba de despliegue en AWS EC2'
} | ConvertTo-Json

$demo = Invoke-RestMethod -Method Post -Uri "http://$publicIp/eventos" -ContentType 'application/json; charset=utf-8' -Body $demoBody
Write-Host "POST /eventos -> 201, id=$($demo.id)" -ForegroundColor Green

$busqueda = Invoke-RestMethod -Uri "http://$publicIp/eventos?fecha=2031-02-01"
Write-Host "GET /eventos?fecha=2031-02-01 -> $($busqueda.Count) evento(s)" -ForegroundColor Green

$demoUpdate = @{
  titulo      = "$demoTitulo editado"
  tipo        = 'evento'
  fecha       = '2031-02-02'
  hora        = '12:00'
  descripcion = 'Editado desde la prueba de despliegue'
} | ConvertTo-Json
$demoActualizado = Invoke-RestMethod -Method Put -Uri "http://$publicIp/eventos/$($demo.id)" -ContentType 'application/json; charset=utf-8' -Body $demoUpdate
Write-Host "PUT /eventos/$($demo.id) -> 200, fecha=$($demoActualizado.fecha)" -ForegroundColor Green

$borrado = Invoke-WebRequest -UseBasicParsing -Method Delete -Uri "http://$publicIp/eventos/$($demo.id)"
Write-Host "DELETE /eventos/$($demo.id) -> $($borrado.StatusCode)" -ForegroundColor Green

$artifactsDir = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null
$info = @{
  publicUrl              = "http://$publicIp"
  publicIp               = $publicIp
  instanceId             = $instanceId
  region                 = $Region
  instanceType           = $InstanceType
  keyPath                = $keyPath
  securityGroupId        = $sgId
  elasticIpAllocationId  = $allocationId
  deployedAt             = (Get-Date).ToString('o')
}
$info | ConvertTo-Json | Set-Content -Path (Join-Path $artifactsDir 'deployment.json') -Encoding UTF8

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Green
Write-Host ' DESPLIEGUE COMPLETADO' -ForegroundColor Green
Write-Host '=====================================================' -ForegroundColor Green
Write-Host " API:  http://$publicIp"
Write-Host " Health: http://$publicIp/health"
Write-Host " SSH:  ssh -i `"$keyPath`" ubuntu@$publicIp"
Write-Host " Logs: ssh -i `"$keyPath`" ubuntu@$publicIp `"sudo journalctl -u api-agenda -f`""
Write-Host ''
Write-Host ' Nota: por ahora es HTTP. Para HTTPS agrega un dominio y Certbot.' -ForegroundColor Yellow
Write-Host " Datos guardados en: $artifactsDir\deployment.json" -ForegroundColor DarkGray
Write-Host ''
