# Flujo de Llamadas: Subida de TXT desde Setup

Este documento describe el flujo de llamadas de funciones desde que se indica subir el TXT en la página de setup hasta la subida a OneDrive.

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
- **`GetLastResultMessage()`** → Devuelve mensaje de éxito ("Subida OK") o error
- **`ExtractGraphAPIError(ErrorObj: JsonObject)`** → Parsea errores específicos de Graph API

## Diagrama de Flujo

```
Página Setup
    ↓
OnAction()
    ↓
ExportTxtFromSetupField()
    ↓
ExportTxtContentToOneDrive()
    ↓
PostTextWithRetry()
    ↓ (loop)
TryPostText()
    ├── ResolveOneDriveUser()
    │   ├── TryResolveUserDirect()
    │   └── TryResolveUserWithFilter()
    ├── AddOAuthAuthorizationHeaderToRequest()
    └── Http.Send() → OneDrive
    ↓
GetLastResultMessage()
    ↓
Message() en UI
```

## Notas
- El flujo usa subida directa de texto para evitar problemas con streams.
- Incluye reintentos automáticos con backoff exponencial.
- Maneja errores específicos de Microsoft Graph API.
- La autenticación se hace a nivel de request para evitar duplicados de headers.