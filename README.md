# AL_Onedrive · Exportar TXT de Business Central a OneDrive

Ejemplo AL que obtiene un token Microsoft Graph con client credentials y sube el texto de la página **OneDrive Webhook Setup** a OneDrive. [Flujo y componentes](Flujo_Subida_TXT.md).

## Estado: revisar credenciales antes de publicar

La inspección estática del 6 de octubre de 2026 encontró configuración personal y un Client Secret incrustado en `src/Page50112-OneDriveWebhookSetup.al`, dentro de `EnsureInit`. No se reproduce aquí. Debe revocarse en Entra ID y retirarse del código mediante una corrección funcional independiente. No publiques este checkout sin esa revisión: la inicialización puede volver a introducir los valores del autor.

## Requisitos

[app.json](app.json) declara application/platform **26.0.0.0**, runtime **15.0**, versión 1.0.0.0 e IDs 50500–50549. Necesitas VS Code con AL Language, un sandbox compatible, autorización para publicar y permitir llamadas HttpClient de esta extensión, y un usuario con OneDrive provisionado.

La aplicación Entra usa `https://graph.microsoft.com/.default`. La guía original indicaba permisos de aplicación `Files.ReadWrite.All` y `User.Read.All`, con consentimiento de administrador. El código resuelve usuarios y escribe archivos; confirma los permisos mínimos de esas rutas con el administrador antes de conceder acceso. No se ha ejecutado una prueba que acredite ese conjunto de permisos.

## Recorrido de uso tras corregir la inicialización

```powershell
git clone https://github.com/javiarmesto/AL_Onedrive.git
cd AL_Onedrive
code .
```

1. Revisa y sustituye la configuración personal de `EnsureInit` sin incrustar nuevos secretos en el código.
2. Configura `.vscode/launch.json` con tu sandbox; descarga símbolos con **AL: Download Symbols**, compila (`Ctrl+Shift+B`) y publica (`F5`).
3. En **OneDrive Webhook Setup**, configura tu Tenant ID, Client ID, secreto y usuario OneDrive; introduce texto de prueba en **TXT Content**. Revisa los campos de carpeta compartida si los utilizas.
4. Pulsa **Subir TXT con contenido de Setup**. El resultado esperado es un TXT en el destino y el mensaje **Subida OK** cuando Graph confirma la operación. Verifica también el archivo en OneDrive.

## Estructura y límites

`src/` contiene tabla de configuración, página y codeunit de orquestación; `app.json` contiene el manifiesto; `.vscode/` y `.alpackages/` conservan ajustes y símbolos del ejemplo. Descarga símbolos para tu entorno en vez de dar por válidos los del autor.

Es un ejemplo de escritura real de archivos, no un mock. El secreto se guarda en un campo `Text[100]` de la tabla; enmascararlo en la página no acredita almacenamiento seguro. Una revisión de producción debe resolver ese diseño y la inicialización. No se han compilado objetos ni contactado Graph/BC. No se ha confirmado una licencia aplicable.

Para diagnosticar `Invalid client`, revisa el secreto y la aplicación; para `User not found`, comprueba usuario y OneDrive; para errores de autorización, revisa permisos y consentimiento sin incluir tokens en el informe.
