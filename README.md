# OneGoalDiscover_Backend_AttendanceApi

API REST de **consulta externa de checadas** de OneGoal Discover. Permite que un sistema de terceros lea los registros de asistencia de los empleados por periodo, sin usar la aplicación de Discover.

La API es de **solo lectura** y tiene su **propio login**: el cliente se autentica con un usuario de Discover y recibe tokens JWT emitidos y validados por esta misma API. Un token de Discover no sirve aquí ni al revés.

## Contenido

- [Qué hace](#qué-hace)
- [Tecnologías](#tecnologías)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Requisitos previos](#requisitos-previos)
- [Configuración](#configuración)
- [Ejecución local](#ejecución-local)
- [Endpoints](#endpoints)
- [Reglas de negocio](#reglas-de-negocio)
- [Seguridad](#seguridad)
- [Base de datos](#base-de-datos)
- [Publicación](#publicación)

## Qué hace

1. **Login** (`POST /api/auth/login`): valida usuario y contraseña contra Discover y entrega un *access token* (60 min) y un *refresh token* (7 días).
2. **Refresh** (`POST /api/auth/refresh`): entrega un access token nuevo sin volver a mandar la contraseña.
3. **Consulta de checadas** (`GET /api/attendance`): devuelve, por empleado y día, el horario programado, las cuatro checadas (entrada, salida a comida, regreso de comida y salida), retardos, horas trabajadas, horas extra, incidencias y si el registro ya está cerrado.

Los datos salen de los mismos procedimientos almacenados que usa la pantalla de auxiliar de horarios de Discover, por lo que las cifras coinciden con las de la aplicación.

## Tecnologías

- .NET 9 / ASP.NET Core (Web API con controladores)
- Autenticación JWT Bearer (HMAC-SHA256)
- Dapper + Microsoft.Data.SqlClient sobre SQL Server
- Swagger / OpenAPI (Swashbuckle) con comentarios XML
- Rate limiting nativo de ASP.NET Core

## Estructura del repositorio

```
.
├── README.md
├── AttendanceApi_Requisitos_1G_KANZ3_dbo.sql   Script con lo que la API necesita en la BD (ver "Base de datos")
├── Manual API de Checadas.pptx                 Manual para quien consume la API
└── OneGoalDiscover_Backend_AttendanceApi/      Proyecto web
    ├── Program.cs                              Arranque: JWT, Swagger, rate limiting
    ├── Controllers/
    │   ├── AuthController.cs                   login y refresh
    │   └── AttendanceController.cs             consulta de checadas
    ├── Services/
    │   ├── AuthService.cs                      validación de usuario y emisión de tokens
    │   ├── AttendanceService.cs                lectura, filtro por sucursal y mapeo de checadas
    │   ├── SqlSchemaExtensions.cs              esquema de los SPs y conexión por empresa
    │   └── ServiceExtensions.cs                inyección de dependencias
    ├── Models/                                 Solicitudes, respuestas y fila cruda del SP
    └── appsettings*.json                       Configuración
```

## Requisitos previos

- [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
- Acceso a una base de datos SQL Server de Discover (ver [Base de datos](#base-de-datos))
- Carpeta de **CFGs** de Discover accesible desde el servidor (contiene la configuración de conexión de cada ambiente)
- Los proyectos hermanos que esta API referencia, ubicados según las rutas del `.csproj`:
  - `OneGoalDiscover_Helpers`
  - `OneGoalDiscover_Models`
  - `OneGoalDiscover_Utilities`

## Configuración

La configuración está en `OneGoalDiscover_Backend_AttendanceApi/appsettings.json`.

| Clave | Descripción | Valor por defecto |
|---|---|---|
| `CFGsPath` | Carpeta raíz donde viven los CFGs de Discover. Cada subcarpeta es un ambiente. | ruta local; ajustar por servidor |
| `Jwt:SecretKey` | Llave de firma de los tokens. **Mínimo 32 caracteres**; si es más corta la API no arranca. | marcador, definir una propia |
| `Jwt:Issuer` | Emisor de los tokens | `OneGoalDiscoverAttendanceApi` |
| `Jwt:Audience` | Audiencia de los access tokens | `OneGoalDiscoverAttendanceApiClients` |
| `Jwt:ExpirationMinutes` | Vigencia del access token | `60` |
| `Jwt:RefreshExpirationDays` | Vigencia del refresh token | `7` |
| `AttendanceApi:DefaultCfg` | Ambiente (CFG) que se usa si el login no manda `Cfg` | `TABAR_DEV` |
| `AttendanceApi:DefaultCompanyId` | Empresa por defecto si el login no manda `CompanyId` | `5` |
| `AttendanceApi:DefaultBranchId` | Sucursal por defecto (`0` = sin restricción de sucursal) | `0` |
| `AttendanceApi:SqlSchema` | Esquema de los SPs: `dsv` en Discover; `dbo` en bases donde aún no existe `dsv` | `dbo` |
| `AttendanceApi:MaxRangeDays` | Máximo de días por consulta | `31` |
| `Database:*` | Parámetros del pool y *timeouts* de conexión | ver archivo |

> **Importante:** el `Jwt:SecretKey` que viene en el repositorio es solo un marcador (`CAMBIAR-POR-LLAVE-PROPIA-...`). Defina una llave propia por ambiente y no la suba al repositorio; use variables de entorno (por ejemplo `Jwt__SecretKey`) o un archivo de configuración fuera del control de versiones.

## Ejecución local

```bash
cd OneGoalDiscover_Backend_AttendanceApi
dotnet restore
dotnet run --launch-profile https
```

URLs por defecto (`Properties/launchSettings.json`):

- HTTPS: `https://localhost:7053`
- HTTP: `http://localhost:5069` (redirige a HTTPS)

La documentación interactiva queda en `/swagger`. Swagger se publica en **todos los ambientes** porque el cliente lo necesita para consumir la API.

## Endpoints

### `POST /api/auth/login`

Sin autenticación. Limitado a 10 intentos por minuto por IP.

```json
{
  "user": "USUARIO",
  "password": "********",
  "cfg": "TABAR_DEV",
  "companyId": 5,
  "branchId": 0
}
```

`cfg`, `companyId` y `branchId` son **opcionales**; si se omiten se usan los valores de `AttendanceApi:Default*`. El usuario admite hasta 10 caracteres.

Respuesta `200`:

```json
{
  "accessToken": "...",
  "expiresAtUtc": "2026-11-23T18:00:00Z",
  "userName": "Nombre del usuario",
  "refreshToken": "...",
  "refreshExpiresAtUtc": "2026-11-30T17:00:00Z"
}
```

### `POST /api/auth/refresh`

Sin autenticación (usa el refresh token). Mismo límite de intentos que el login.

```json
{ "refreshToken": "..." }
```

Devuelve `accessToken`, `expiresAtUtc` y `userName`. El usuario se **revalida en cada llamada**. El refresh token no se renueva: a los 7 días del login hay que iniciar sesión de nuevo.

### `GET /api/attendance`

Requiere `Authorization: Bearer <accessToken>` (en Swagger se pega solo el token).

| Parámetro | Obligatorio | Descripción |
|---|---|---|
| `startDate` | Sí | Fecha inicial, `yyyy-MM-dd` |
| `endDate` | Sí | Fecha final, `yyyy-MM-dd` |
| `employeeId` | No | `id_emp` de un empleado. Si se omite, todos los que el usuario puede ver |
| `page` | No | Página, desde 1 (por defecto 1) |
| `pageSize` | No | Registros por página, 1 a 5000 (por defecto 1000) |

Ejemplo:

```bash
curl -H "Authorization: Bearer <accessToken>" \
  "https://localhost:7053/api/attendance?startDate=2026-11-01&endDate=2026-11-15&employeeId=123&page=1&pageSize=500"
```

Respuesta `200` (ilustrativa y resumida):

```json
{
  "startDate": "2026-11-01",
  "endDate": "2026-11-15",
  "isPeriodClosed": false,
  "closedRecords": 120,
  "openRecords": 30,
  "page": 1,
  "pageSize": 500,
  "totalRecords": 150,
  "records": [
    {
      "employeeId": 123,
      "employeeCode": "E001",
      "employeeName": "Nombre Apellido",
      "date": "2026-11-03",
      "shift": "Matutino",
      "scheduledEntry": "09:00",
      "scheduledMealStart": "14:00",
      "scheduledMealEnd": "15:00",
      "scheduledExit": "18:00",
      "checkIn":  { "time": "2026-11-03T08:58:00", "type": "Huella", "deviceCode": "BIO-01" },
      "mealOut":  null,
      "mealIn":   null,
      "checkOut": { "time": "2026-11-03T18:05:00", "type": "Cara", "deviceCode": "BIO-01" },
      "lateMinutes": 0,
      "earlyMinutes": 0,
      "scheduledHours": "08:00",
      "workedHours": "09:07",
      "overtimeHours": 0.0,
      "incidentType": null,
      "dayType": "Normal",
      "isClosed": true
    }
  ]
}
```

### Códigos de respuesta

| Código | Cuándo |
|---|---|
| `200` | Correcto |
| `400` | Parámetros inválidos (fechas, rango, `employeeId`, paginación) o `cfg`/empresa/sucursal inválidos en el login |
| `401` | Credenciales incorrectas, refresh token inválido o vencido, o falta el access token |
| `403` | El usuario no tiene acceso a la empresa o sucursal indicada |
| `409` | Usuario caducado, o debe establecer una nueva contraseña |
| `429` | Se superó el límite de intentos de login/refresh |

Los errores de negocio devuelven `{ "message": "..." }`.

## Reglas de negocio

- **Rango máximo:** 31 días por consulta (`AttendanceApi:MaxRangeDays`).
- **Seguridad por sucursal:** solo se devuelven empleados de las sucursales a las que el usuario tiene permiso, igual que en la pantalla de Discover. Si el login indicó una sucursal, además se limita a ella.
- **Valores vacíos:** Discover usa `00:00:00` como "sin dato"; la API lo entrega como `null` en horarios y checadas.
- **Tipo de checada (`type`):** `Huella`, `Manual`, `Cara` o `Automática` (cualquier otro código se devuelve tal cual).
- **Tipo de día (`dayType`):** `Festivo`, `Descanso`, `Vacación`, `Permiso` o `Normal`.
- **Incidencias (`incidentType`):** ausencia justificada/injustificada, retardo con o sin goce, vacaciones, otras incidencias del catálogo u horas extra autorizadas, con la misma precedencia que el asistente de horarios de Discover.
- **Cierre:** un registro está cerrado (`isClosed`) si su nómina está cerrada o el periodo se cerró manualmente. `isPeriodClosed` es `true` solo si **todos** los registros del rango están cerrados.
- **Paginación:** los totales (`totalRecords`, `closedRecords`, `openRecords`) corresponden a todo el rango, no solo a la página devuelta.

## Seguridad

- Llave, emisor y audiencia JWT **propios**; el refresh token usa otra audiencia (`<Audience>.refresh`), de modo que no puede usarse como access token ni al revés.
- El access token vence exactamente en `exp` (sin tolerancia de reloj).
- El refresh token lleva una huella de la contraseña (no la contraseña): si el usuario la cambia o se la restablecen, el refresh token deja de servir.
- Usuario inexistente, usuario KIOSKO o contraseña incorrecta responden igual, para no revelar qué usuarios existen.
- El `cfg` solo se acepta si existe como carpeta en `CFGsPath` y viaja cifrado dentro del token.
- Rate limiting de login y refresh: 10 solicitudes por minuto por IP.
- Se exige HTTPS (`RequireHttpsMetadata` y redirección HTTPS).

## Base de datos

La API usa estos procedimientos almacenados (esquema configurable con `AttendanceApi:SqlSchema`):

| SP | Uso |
|---|---|
| `pDSV_CFG_Usuario` | Datos del usuario para validar el login |
| `pDSV_CFG_ConfiguracionEmpresaUsuario` | Empresas a las que el usuario tiene acceso |
| `pDSV_CFG_ConfiguracionSucursalesUsuario` | Sucursales a las que el usuario tiene acceso |
| `pDSV_CFG_ConfiguracionEmpresa` | Base de datos de la empresa (se resuelve y se cachea) |
| `pDSVRRHHauxiliarHorarioObtenerInformacion` | Checadas y horarios del periodo |
| `pDSVRRHHauxiliarHorarioInformacionTipoIncidencias` | Catálogo de tipos de incidencia |
| `pDSVRRHHauxiliarHorarioInformacionSucursales` | Sucursales permitidas al usuario |
| `pDSVRRHHauxiliarHorarioSucursalesEmpleado` | Sucursal de cada empleado |

Para bases que aún no tienen el módulo completo (por ejemplo `1G_KANZ3`), el archivo [`AttendanceApi_Requisitos_1G_KANZ3_dbo.sql`](AttendanceApi_Requisitos_1G_KANZ3_dbo.sql) agrega lo necesario: columnas nuevas en `rh_hr_hst` y `cat_hor`, la tabla `tDSV_VAC_tipos_ausencia`, una vista **temporal vacía** `vDSV_VAC_ausencias_autorizadas` (reemplazar al desplegar el módulo de Vacaciones) y los SPs de horarios. Incluye una guarda que impide ejecutarlo en una base distinta a `1G_KANZ3` y un bloque de rollback comentado al final. Los SPs de origen están en el repositorio `1G_ATM-Estructura`.

## Publicación

El perfil `FolderProfile` publica en `C:\Publicaciones\OGD` en modo Release:

```bash
dotnet publish -c Release -p:PublishProfile=FolderProfile
```

Antes de publicar revise `Jwt:SecretKey`, `CFGsPath`, `AttendanceApi:DefaultCfg`, `DefaultCompanyId` y `SqlSchema` para el ambiente destino.

## Documentación adicional

El archivo `Manual API de Checadas.pptx` es el manual para quien consume la API.
