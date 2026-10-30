# Despliegue de la API de Agenda en AWS EC2

Este directorio contiene el despliegue automatizado de la API en una instancia **EC2 con Ubuntu 24.04**, con **MySQL en la misma instancia**, **Node.js 22**, **Nginx** como proxy inverso y **systemd** para mantener el proceso activo.

## Arquitectura

```text
Internet
   │ HTTP :80
   ▼
Nginx (EC2)
   │ proxy a 127.0.0.1:3000
   ▼
Node.js / Express (servicio api-agenda)
   │
   ▼
MySQL local (127.0.0.1:3306, base agenda)
```

La API escucha en `127.0.0.1:3000` y Nginx publica el puerto 80. MySQL no se expone a internet.

## Requisitos

- Cuenta de AWS.
- Usuario IAM con permisos para EC2. Para simplificar, se puede usar la política `AmazonEC2FullAccess` en una cuenta de práctica.
- Access Key ID y Secret Access Key del usuario IAM.
- OpenSSH en Windows (ya está instalado).
- Python y AWS CLI. En este equipo AWS CLI ya quedó instalado a nivel de usuario.

## 1. Configurar credenciales de AWS

Ejecuta en una terminal de PowerShell:

```powershell
cd "C:\Users\crist\OneDrive\Escritorio\Android API"
powershell -ExecutionPolicy Bypass -File .\deploy\configurar-aws.ps1
```

El script pide:

1. **Access Key ID**.
2. **Secret Access Key**.
3. Región: se puede dejar `us-east-1` presionando Enter.
4. Formato de salida: `json`.

Las credenciales se guardan en `C:\Users\crist\.aws\` y no en el proyecto.

Verificación manual:

```powershell
python -m awscli sts get-caller-identity
```

## 2. Desplegar

```powershell
cd "C:\Users\crist\OneDrive\Escritorio\Android API"
powershell -ExecutionPolicy Bypass -File .\deploy\deploy-ec2.ps1
```

El proceso:

1. Verifica las credenciales.
2. Reutiliza una instancia existente con la etiqueta `api-agenda` o crea una nueva.
3. Crea el Security Group con SSH restringido a tu IP actual y HTTP abierto.
4. Crea una llave SSH `agenda-api-key` si no existe.
5. Lanza Ubuntu 24.04, tipo `t3.micro`, disco de 20 GB.
6. Asigna una Elastic IP para que la dirección no cambie.
7. Sube la API por SCP.
8. Instala Node.js 22, MySQL, Nginx y las dependencias.
9. Crea la base `agenda`, importa `database/agenda.sql` y crea el usuario `agenda_app`.
10. Configura el servicio `api-agenda` y Nginx.
11. Prueba `GET /health`, `POST`, `GET`, `PUT` y `DELETE` por HTTP público.

Al finalizar muestra algo como:

```text
API:    http://54.123.45.67
Health: http://54.123.45.67/health
SSH:    ssh -i "C:\Users\crist\.ssh\agenda-api-key.pem" ubuntu@54.123.45.67
```

Los datos del despliegue se guardan en `deploy/artifacts/deployment.json`.

## 3. Comprobar la API

```powershell
Invoke-RestMethod http://IP_PUBLICA/health
Invoke-RestMethod http://IP_PUBLICA/eventos
```

También puedes abrir en el navegador:

```text
http://IP_PUBLICA/eventos
```

## 4. Actualizar la API después de un cambio

Vuelve a ejecutar:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\deploy-ec2.ps1
```

El script reutiliza la instancia y la Elastic IP, vuelve a subir el código, instala dependencias y reinicia el servicio. La base de datos se conserva.

## 5. Logs y administración

Conéctate por SSH:

```powershell
ssh -i "C:\Users\crist\.ssh\agenda-api-key.pem" ubuntu@IP_PUBLICA
```

Comandos útiles:

```bash
sudo systemctl status api-agenda
sudo journalctl -u api-agenda -f
sudo systemctl restart api-agenda
sudo nginx -t
sudo systemctl reload nginx
```

La configuración sensible de la API está en:

```text
/etc/api-agenda.env
```

Tiene permisos `600` y pertenece a `root`. La contraseña de MySQL se genera automáticamente en cada despliegue y solo la usa el usuario `agenda_app`.

## 6. HTTPS

Por ahora la API queda publicada por **HTTP** en la IP de EC2, tal como se eligió. Para producción se recomienda:

1. Registrar un dominio o usar un subdominio.
2. Apuntar el dominio a la Elastic IP con un registro `A`.
3. Instalar Certbot y emitir un certificado de Let's Encrypt.
4. Redirigir HTTP a HTTPS.
5. Abrir el puerto 443 en el Security Group.
6. Configurar la app Android para usar `https://...`.

Android bloquea HTTP sin cifrar en versiones recientes. Para probar la API por HTTP desde el emulador o un teléfono, hay que permitir tráfico `cleartext` en el `network_security_config.xml` solo para desarrollo.

## 7. Costos y limpieza

La instancia, la Elastic IP y el volumen EBS pueden generar costos. Para eliminar todo cuando ya no se use:

```powershell
# Ver los datos guardados
Get-Content .\deploy\artifacts\deployment.json

# Terminar la instancia
python -m awscli ec2 terminate-instances --instance-ids INSTANCE_ID

# Liberar la Elastic IP
python -m awscli ec2 release-address --allocation-id ALLOCATION_ID

# Eliminar el Security Group, solo después de terminar la instancia
python -m awscli ec2 delete-security-group --group-id SECURITY_GROUP_ID

# Eliminar la llave de AWS si ya no se necesita
python -m awscli ec2 delete-key-pair --key-name agenda-api-key
```

> Terminar la instancia borra también la base de datos MySQL local. Si necesitas conservar los datos, haz un respaldo con `mysqldump` antes.

## 8. Solución de problemas

| Problema | Causa probable | Solución |
|---|---|---|
| `AWS CLI fallo` al inicio | Credenciales no configuradas o sin permisos | Ejecuta `configurar-aws.ps1` y revisa la política IAM. |
| No hay VPC por defecto | Cuenta AWS sin VPC default | Crea una VPC/subred o adapta el script. |
| SSH no responde | Cambió tu IP pública o el puerto 22 está cerrado | Agrega tu nueva IP al Security Group. |
| La llave existe en AWS pero no el `.pem` | Se creó la llave en otro equipo | Usa el `.pem` original o elimina la llave en AWS y vuelve a desplegar. |
| La instancia va lenta | `t3.micro` tiene 1 GB de RAM | Usa `-InstanceType t3.small` al desplegar. |
| Error al importar MySQL | MySQL no inició o root no usa socket | Revisa `sudo systemctl status mysql` y `/var/log/mysql/error.log`. |
| `InvalidPermission.Duplicate` | La regla del Security Group ya existía | Es normal; el script continúa. |

## 9. Notas de seguridad

- El puerto 22 solo se abre para la IP desde la que se ejecuta el despliegue.
- El puerto 80 está abierto a internet porque es la API pública.
- MySQL solo escucha en `127.0.0.1`.
- La API no tiene autenticación porque el documento la deja fuera de alcance. Si se publica para uso real, agrega autenticación y límites de peticiones.
- No subas `.env`, llaves `.pem` ni `deploy/artifacts/` al repositorio.
