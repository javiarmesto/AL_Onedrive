# Business Central → OneDrive Integration

## Configuración

1. **Crear App Registration en Azure Portal**
   - Name: "BusinessCentral OneDrive Integration"
   - Account types: "Single tenant"
   - API permissions: Files.ReadWrite.All, User.Read.All (Application permissions).Read.All (Application permissions)
   - Grant admin consent

2. **Obtener credenciales**
   - Application (client) ID
   - Directory (tenant) ID
   - Client Secret

3. **Configurar en Business Central**
   - Buscar: "OneDrive Webhook Setup"
   - Completar campos: Tenant ID, Client ID, Client Secret, OneDrive User Email
   - Rellenar "TXT Content" con el contenido deseado

## Uso

- En la página Setup, pulsar "Subir TXT con contenido de Setup"
- Resultado esperado: "Subida OK" (en caso de éxito)

## Troubleshooting

- **Authorization_RequestDenied**: Verificar permisos y admin consent
- **Invalid client**: Revisar Client Secret
- **User not found**: Verificar email del usuario OneDrive
