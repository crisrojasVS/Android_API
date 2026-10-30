# API de Agenda (citas y eventos)

Backend REST en **Node.js + Express + MySQL** para la aplicación Android de agenda. Implementa el contrato descrito en el documento **“API de Agenda: contexto y endpoints”**: un solo recurso `Evento`, con creación, consulta, edición, eliminación y búsquedas por fecha y por título.

## Requisitos

- Node.js 20 o superior (probado con Node.js 24).
- MySQL 8 o superior.
- npm.

## Puesta en marcha

```powershell
npm install
npm run db:init
npm start
```

La API queda disponible en `http://localhost:3000`.

Para desarrollo con recarga automática al guardar cambios:

```powershell
npm run dev
```

También puedes abrir el proyecto en VS Code y presionar **F5** con la configuración **“API de Agenda”** incluida en `.vscode/launch.json`.

Comprobación rápida:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

Respuesta esperada:

```json
{ "status": "ok", "database": "ok" }
```

> `npm run db:init` crea la base de datos `agenda`, la tabla `eventos`, el índice por fecha y los datos de prueba del archivo `database/agenda.sql`. Se puede ejecutar varias veces: no duplica los datos de prueba ni falla si el índice ya existe.

## Configuración

La configuración se toma de variables de entorno (archivo `.env` en la raíz del proyecto). `.env` no se sube al repositorio; `.env.example` sirve como plantilla.

```env
PORT=3000
HOST=0.0.0.0

DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=tu_contrasena
DB_NAME=agenda
DB_CONNECTION_LIMIT=10
```

En esta instalación ya se creó el archivo `.env` local con la conexión a MySQL; está excluido por `.gitignore` y no se comparte.

En AWS, estos valores deben configurarse como variables de entorno del servicio (por ejemplo, Elastic Beanstalk o EC2), nunca dentro del código. Para producción se recomienda crear un usuario de MySQL dedicado con permisos únicamente sobre `agenda.*`, en lugar de usar una cuenta administrativa.

## Endpoints

| Método | Ruta | Descripción | Éxito | Errores |
|---|---|---|---|---|
| `POST` | `/eventos` | Crear un evento o cita | `201 Created` | `400` |
| `GET` | `/eventos` | Listar todos los eventos, ordenados por fecha y hora | `200 OK` | — |
| `GET` | `/eventos?fecha=AAAA-MM-DD` | Buscar los eventos de una fecha | `200 OK` | `400` |
| `GET` | `/eventos?titulo=texto` | Buscar por título (parcial, sin distinguir mayúsculas) | `200 OK` | — |
| `GET` | `/eventos?fecha=...&titulo=...` | Aplicar ambos filtros a la vez | `200 OK` | `400` |
| `GET` | `/eventos/{id}` | Consultar un evento por id | `200 OK` | `400`, `404` |
| `PUT` | `/eventos/{id}` | Editar un evento (se envían todos los campos) | `200 OK` | `400`, `404` |
| `DELETE` | `/eventos/{id}` | Eliminar un evento | `204 No Content` | `400`, `404` |

Además existen `GET /` (información básica de la API) y `GET /health` (comprueba la conexión con MySQL).

### Recurso Evento

```json
{
  "id": 1,
  "titulo": "Dentista",
  "tipo": "cita",
  "fecha": "2026-11-05",
  "hora": "16:30",
  "descripcion": "Revisión general"
}
```

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `id` | número | No (lo genera el servidor) | Identificador único. |
| `titulo` | texto | Sí | No vacío, máximo 100 caracteres. |
| `tipo` | texto | Sí | Solo `cita` o `evento`. |
| `fecha` | texto | Sí | Formato `AAAA-MM-DD` y fecha real (no `2026-02-30`). |
| `hora` | texto | No | Formato `HH:mm` (24 horas). Si se omite o es `null`, se guarda `null`. |
| `descripcion` | texto | No | Máximo 255 caracteres. Si se omite o es `null`, o si está vacía, se guarda `null`. |

Los listados y búsquedas se devuelven ordenados por `fecha` y luego por `hora`.

## Ejemplos de uso

### Crear

```powershell
$body = @{
  titulo      = 'Dentista'
  tipo        = 'cita'
  fecha       = '2026-11-05'
  hora        = '16:30'
  descripcion = 'Revisión general'
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
  -Uri http://localhost:3000/eventos `
  -ContentType 'application/json; charset=utf-8' `
  -Body $body
```

### Listar y buscar

```powershell
Invoke-RestMethod http://localhost:3000/eventos
Invoke-RestMethod 'http://localhost:3000/eventos?fecha=2026-11-05'
Invoke-RestMethod 'http://localhost:3000/eventos?titulo=dent'
Invoke-RestMethod 'http://localhost:3000/eventos/1'
```

### Editar

```powershell
$body = @{
  titulo      = 'Dentista'
  tipo        = 'cita'
  fecha       = '2026-11-07'
  hora        = '10:00'
  descripcion = 'Cita reprogramada'
} | ConvertTo-Json

Invoke-RestMethod -Method Put `
  -Uri http://localhost:3000/eventos/1 `
  -ContentType 'application/json; charset=utf-8' `
  -Body $body
```

### Eliminar

```powershell
Invoke-WebRequest -Method Delete -Uri http://localhost:3000/eventos/1
```

## Formato de errores

Todos los errores se devuelven como JSON:

```json
{ "error": "El campo 'fecha' debe tener el formato AAAA-MM-DD y ser una fecha válida" }
```

```json
{ "error": "No existe un evento con el id 7" }
```

## Pruebas

```powershell
npm test
```

Las pruebas son de integración: usan el mismo servidor Express y la base de datos MySQL real. Crean eventos con el prefijo `TEST-API`, verifican todos los endpoints y validaciones, y los eliminan al terminar.

Cobertura de las pruebas:

- `POST /eventos` y generación del `id`.
- Listado, orden por fecha/hora y búsqueda por fecha.
- Búsqueda parcial por título sin distinguir mayúsculas.
- Combinación de filtros `fecha` + `titulo`.
- Consulta, edición y eliminación por id.
- `404` para ids inexistentes y `400` para ids inválidos.
- Validación de campos obligatorios, tipo, fechas reales, hora y longitudes.
- Fechas inválidas en el parámetro `fecha`.
- Cuerpo JSON mal formado.
- Conexión a MySQL mediante `GET /health`.

## Estructura del proyecto

```text
Android API/
├── database/
│   └── agenda.sql              # Esquema y datos de prueba originales
├── scripts/
│   └── init-db.js              # Inicialización idempotente de MySQL
├── src/
│   ├── app.js                  # Configuración de Express
│   ├── config.js               # Variables de entorno
│   ├── db.js                   # Pool de conexiones MySQL
│   ├── errors.js               # Errores HTTP y middleware de errores
│   ├── eventos.repository.js   # Consultas SQL
│   ├── eventos.routes.js       # Rutas /eventos
│   ├── eventos.validators.js   # Validaciones
│   └── server.js               # Arranque y cierre ordenado
├── tests/
│   └── eventos.test.js         # Pruebas de integración
├── .vscode/
│   └── launch.json             # Ejecutar/depurar la API desde VS Code
├── .env.example
├── package.json
└── README.md
```

## Despliegue en AWS EC2

El proyecto incluye un despliegue automatizado para **EC2 con Ubuntu 24.04**, MySQL en la misma instancia, Node.js 22, Nginx y systemd.

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\configurar-aws.ps1
powershell -ExecutionPolicy Bypass -File .\deploy\deploy-ec2.ps1
```

La guía completa, requisitos de IAM, actualización, HTTPS, logs y limpieza de recursos está en [`deploy/README.md`](deploy/README.md).

## Notas para la app Android

- **Emulador Android**: el host del equipo se ve como `10.0.2.2`. La URL local sería `http://10.0.2.2:3000`.
- **Dispositivo físico**: usa la IP de la red local del equipo, por ejemplo `http://192.168.1.50:3000`, y permite el puerto en el firewall.
- Android bloquea por defecto el tráfico HTTP sin cifrar en versiones recientes. Para desarrollo local se puede usar `android:usesCleartextTraffic="true"` o un `network_security_config.xml`; en producción debe usarse **HTTPS**.
- **AWS**: la app Android debe apuntar a la URL pública de la API (nunca `localhost`), con HTTPS. La base de datos puede ser RDS para MySQL, y la conexión debe configurarse con variables de entorno.
- CORS está habilitado para clientes web; una app Android nativa no lo necesita.

## Base de datos

El esquema está en `database/agenda.sql`:

- Base de datos: `agenda`.
- Tabla: `eventos`.
- Campos: `id`, `titulo`, `tipo`, `fecha`, `hora`, `descripcion`.
- Índice: `idx_eventos_fecha` sobre `fecha`.
- Datos de prueba: cuatro eventos de noviembre de 2026.

Si ya tienes la base creada con el script original, solo configura `.env` y ejecuta `npm start`.
