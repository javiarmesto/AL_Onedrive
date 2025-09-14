# Flujo de Llamadas: Subida de TXT desde Setup

Este documento describe el flujo completo de llamadas de funciones desde que se indica subir el TXT en la página de setup hasta la subida exitosa a OneDrive.

## Requisitos Previos

### Permisos de Azure App Registration
- **Files.ReadWrite.All** (Application): Permite leer/escribir archivos en OneDrive
- **User.Read.All** (Application): Permite buscar usuarios por email
- **Admin consent**: Debe estar concedido para ambos permisos

### Configuración Requerida
- Tenant ID, Client ID, Client Secret del App Registration
- Email del usuario de OneDrive (debe existir en el tenant)
- Contenido TXT en el campo "TXT Content" de la página Setup

## Inicio: Página de Setup

### Página: OneDrive Webhook Setup (Page 50512)
- **Acción**: `UploadTXTFromSetup` (trigger OnAction)
  - Llama a: `EnsureInit()` (inicializa configuración si no existe)
  - Llama a: `Orchestrator.ExportTxtFromSetupField()`
  - Muestra mensaje: `Message(Orchestrator.GetLastResultMessage())`

## Codeunit: TXT → Webhook Orchestrator (Codeunit 50510)

### 1. `ExportTxtFromSetupField()`
- **Propósito**: Obtiene el contenido del campo "TXT Content" de la tabla Setup y lo sube.
- **Llamadas**:
  - `GetSetup()` → Obtiene el registro de configuración
  - `ExportTxtContentToOneDrive('SetupTXT', Content)` → Sube el contenido

### 2. `ExportTxtContentToOneDrive(FileBaseName: Text; Content: Text)`
- **Propósito**: Prepara el archivo y llama al método de subida.
- **Llamadas**:
  - `GetOneDriveFolderPath()` → Obtiene la ruta de carpeta destino
  - `SanitizeForFileName()` → Limpia el nombre de archivo
  - `PostTextWithRetry(Content, FileName, FolderPath, Mime, Resp, 3)` → Sube con reintentos

### 3. `PostTextWithRetry(ContentText: Text; FileName: Text; FolderPath: Text; ContentType: Text; var ResponseText: Text; Retries: Integer)`
- **Propósito**: Maneja reintentos con backoff exponencial.
- **Llamadas** (en loop):
  - `TryPostText(ContentText, FileName, FolderPath, ContentType, ResponseText)` → Intenta la subida
  - Si falla: `Sleep(DelayMs)` y retry

### 4. `TryPostText(ContentText: Text; FileName: Text; FolderPath: Text; ContentType: Text; var ResponseText: Text)`
- **Propósito**: Realiza la subida HTTP a Microsoft Graph API.
- **Llamadas**:
  - `GetOneDriveUserEmail()` → Obtiene email del usuario
  - `ResolveOneDriveUser(UserEmail, ResolvedUserId, ResponseText)` → Resuelve ID del usuario
  - `AddOAuthAuthorizationHeaderToRequest(HttpReq, ResponseText)` → Agrega token OAuth
  - `Http.Send(HttpReq, HttpResp)` → Envía la petición PUT

## Funciones Auxiliares

### Resolución de Usuario
- **`ResolveOneDriveUser(UserUpn: Text; var ResolvedId: Text; var ErrorText: Text)`**
  - Llama a: `TryResolveUserDirect()` (primero)
  - Si falla: `TryResolveUserWithFilter()` (segundo)

- **`TryResolveUserDirect(UserUpn: Text; var ResolvedId: Text; var ErrorText: Text)`**
  - Construye URL: `https://graph.microsoft.com/v1.0/users/{UserUpn}`
  - Llama a: `AddOAuthAuthorizationHeader(Http, TokenResp)`
  - Llama a: `Http.Get(Url, Resp)`

- **`TryResolveUserWithFilter(UserUpn: Text; var ResolvedId: Text; var ErrorText: Text)`**
  - Construye URL: `https://graph.microsoft.com/v1.0/users?$filter=userPrincipalName eq '{UserUpn}'`
  - Llama a: `AddOAuthAuthorizationHeader(Http, TokenResp)`
  - Llama a: `Http.Get(Url, Resp)`

### Autenticación OAuth
- **`AddOAuthAuthorizationHeaderToRequest(var HttpReq: HttpRequestMessage; var ErrorText: Text)`**
  - Llama a: `GetSetup()` → Obtiene credenciales
  - Llama a: `OAuth2.AcquireTokenWithClientCredentials()` → Obtiene token
  - Agrega header: `Authorization: Bearer {AccessToken}`

### Configuración y Utilidades
- **`GetSetup()`** → Obtiene registro de configuración
- **`GetOneDriveUserEmail()`** → Devuelve email del usuario
- **`GetOneDriveFolderPath()`** → Devuelve ruta de carpeta (personalizada o por defecto)
- **`SanitizeForFileName(Value: Text)`** → Limpia caracteres inválidos

### Resultados y Errores
- **`GetLastResultMessage()`** → Devuelve "Subida OK" en caso de éxito o código de error HTTP

## Diagrama de Flujo Completo

```
Usuario hace clic en "Subir TXT con contenido de Setup"
    ↓
Página Setup (Page 50512)
    ↓
OnAction() → Orchestrator.ExportTxtFromSetupField()
    ↓
Codeunit 50510: TXT → Webhook Orchestrator
    ↓
1. ExportTxtFromSetupField()
   ├── GetSetup() → Valida configuración completa
   └── ExportTxtContentToOneDrive('SetupTXT', Content)
       ↓
2. ExportTxtContentToOneDrive()
   ├── SanitizeForFileName() → Limpia nombre de archivo
   ├── GetOneDriveFolderPath() → Obtiene ruta destino
   └── PostTextWithRetry(Content, FileName, FolderPath, 'text/plain; charset=utf-8', Resp, 3)
       ↓
3. PostTextWithRetry() [Loop hasta 3 intentos]
   └── TryPostText() → Intento de subida HTTP
       ├── GetOneDriveUserEmail() → Email del usuario
       ├── ResolveOneDriveUser() → ID del usuario
       │   ├── TryResolveUserDirect() → GET /users/{email}
       │   └── TryResolveUserWithFilter() → GET /users?$filter=...
       ├── AddOAuthAuthorizationHeaderToRequest() → Token OAuth
       │   └── OAuth2.AcquireTokenWithClientCredentials()
       └── Http.Send(PUT /users/{id}/drive/root:/{path}:/content)
           ↓
Resultado HTTP (200-299 = Éxito)
    ↓
GetLastResultMessage() → "Subida OK" o "Error HTTP {código}"
    ↓
Message() en UI → Muestra resultado al usuario
```

## Troubleshooting

### Errores Comunes

- **Authorization_RequestDenied**: Verificar permisos Files.ReadWrite.All y User.Read.All con admin consent
- **Invalid client**: Revisar Client Secret y Tenant ID
- **User not found**: Verificar que el email del usuario existe en el tenant de Azure AD
- **Empty file uploaded**: Problema resuelto con subida directa de texto
- **HTTP 401/403**: Verificar configuración OAuth y permisos de aplicación

### Logs de Debug

- `LastResponseText`: Contiene la respuesta completa del servidor
- `LastStatusCode`: Código HTTP de la última petición
- `GetLastResultMessage()`: Mensaje simplificado para el usuario

### Puntos de Verificación

1. App Registration creada con permisos correctos
2. Admin consent concedido
3. Credenciales correctas en tabla Setup
4. Usuario de OneDrive existe y es accesible
5. Campo "TXT Content" tiene contenido
6. Conexión a internet y Graph API accesible
