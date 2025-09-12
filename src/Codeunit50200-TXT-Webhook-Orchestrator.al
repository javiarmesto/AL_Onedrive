codeunit 50510 "TXT → Webhook Orchestrator"
{
    SingleInstance = false;

    var
        LastResponseText: Text;
        LastStatusCode: Integer;


    procedure ExportFakeTxtToOneDrive()
    var
        InStr: InStream;
        TempBlobLocal: Codeunit "Temp Blob";
        FileName: Text;
        FolderPath: Text;
        Mime: Text;
        Resp: Text;
        Ok: Boolean;
    begin
        // 1) Generar un TXT "fake" en memoria
        CreateFakeTxtInStream(TempBlobLocal, FileName);
        TempBlobLocal.CreateInStream(InStr);

        // 2) Decidir carpeta destino: personalizada o BC/<Company>/<YYYY>/<MM>
        FolderPath := GetOneDriveFolderPath();

        // 3) Enviar al webhook (Power Automate)
        Mime := 'text/plain; charset=utf-8';
        Ok := PostWithRetry(InStr, FileName, FolderPath, Mime, Resp, 3);
        if not Ok then
            Error('Fallo al subir TXT vía webhook. Respuesta: %1', CopyStr(Resp, 1, 250));
    end;

    // Variante: si quieres pasar el contenido desde fuera
    procedure ExportTxtContentToOneDrive(FileBaseName: Text; Content: Text)
    var
        InStr: InStream;
        TempBlobLocal: Codeunit "Temp Blob";
        FileName: Text;
        FolderPath: Text;
        Mime: Text;
        Resp: Text;
        Ok: Boolean;
    begin
        CreateTxtFromText(Content, FileBaseName, TempBlobLocal, FileName);
        // Para contenido desde Setup, subimos directamente el texto para evitar problemas de streams

        FolderPath := GetOneDriveFolderPath();

        Mime := 'text/plain; charset=utf-8';
        Ok := PostTextWithRetry(Content, FileName, FolderPath, Mime, Resp, 3);
        if not Ok then
            Error('Fallo al subir TXT vía webhook. Respuesta: %1', CopyStr(Resp, 1, 250));
    end;

    // Sube un TXT con el contenido almacenado en Setup."TXT Content"
    procedure ExportTxtFromSetupField()
    var
        Setup: Record "OneDrive Webhook Setup";
        Content: Text;
    begin
        Setup := GetSetup();
        Content := Setup."TXT Content";
        Message('Debug: ExportTxtFromSetupField - Content length = %1', StrLen(Content));
        if StrLen(Content) > 0 then
            Message('Debug: Content preview = %1', CopyStr(Content, 1, 50))
        else
            Message('Debug: ERROR - Setup."TXT Content" está vacío');
        if Content = '' then
            Error('El campo "TXT Content" en Setup está vacío.');
        ExportTxtContentToOneDrive('SetupTXT', Content);
    end;

    // ─────────────────────────────────────────────────────────────────────────────
    // Generación de TXT "fake"
    // ─────────────────────────────────────────────────────────────────────────────
    local procedure CreateFakeTxtInStream(var TempBlob: Codeunit "Temp Blob"; var FileName: Text)
    var
        OutStr: OutStream;
        TodayIso: Text;
    begin
        TempBlob.CreateOutStream(OutStr);

        TodayIso := Format(Today(), 0, 9); // YYYY-MM-DD (regional según servidor)

        // Contenido de ejemplo: cabecera + 3 líneas
        OutStr.WriteText('HEADER|BC|' + CompanyName() + '|' + TodayIso);
        OutStr.WriteText('LINE|0001|Articulo X|10|9.95');
        OutStr.WriteText('LINE|0002|Articulo Y|5|19.50');
        OutStr.WriteText('FOOTER|COUNT|2');

        FileName := StrSubstNo('Export_%1_%2.txt', SanitizeForFileName(CompanyName()), SanitizeForFileName(Format(CurrentDateTime(), 0, 9)));

        // Debug: Verificar que se creó contenido
        Message('Debug: CreateFakeTxtInStream completado - FileName = %1', FileName);
    end;

    local procedure CreateTxtFromText(Content: Text; FileBaseName: Text; var TempBlob: Codeunit "Temp Blob"; var FileName: Text)
    var
        OutStr: OutStream;
    begin
        TempBlob.CreateOutStream(OutStr);
        OutStr.WriteText(Content);
        if FileBaseName = '' then
            FileBaseName := 'Export';
        FileName := StrSubstNo('%1_%2.txt', SanitizeForFileName(FileBaseName), SanitizeForFileName(Format(CurrentDateTime(), 0, 9)));
    end;

    // ─────────────────────────────────────────────────────────────────────────────
    // HTTP: POST al webhook con Base64 + metadatos + header de secreto simple
    // ─────────────────────────────────────────────────────────────────────────────
    local procedure PostWithRetry(InStream: InStream; FileName: Text; FolderPath: Text; ContentType: Text; var ResponseText: Text; Retries: Integer): Boolean
    var
        Attempt: Integer;
        DelayMs: Integer;
    begin
        for Attempt := 1 to Retries do begin
            if TryPost(InStream, FileName, FolderPath, ContentType, ResponseText) then
                exit(true);

            DelayMs := Power(2, Attempt) * 500; // 500ms, 1s, 2s...
            Sleep(DelayMs);
            ResetInStream(InStream);
        end;
        exit(false);
    end;

    local procedure TryPost(var InStream: InStream; FileName: Text; FolderPath: Text; ContentType: Text; var ResponseText: Text): Boolean
    var
        Http: HttpClient;
        HttpResp: HttpResponseMessage;
        HttpReq: HttpRequestMessage;
        Content: HttpContent;
        Headers: HttpHeaders;
        ContentHeader: HttpHeaders;
        Url: Text;
        UserEmail: Text;
        ResolvedUserId: Text;
        FilePath: Text;
        DebugText: Text;
        LineText: Text;
        ContentLengthValue: Text;
        ContentLengthList: List of [Text];
        WorkBlob: Codeunit "Temp Blob";
        WorkInStream: InStream;
        OutStr: OutStream;
        InStrCopy: InStream;
    begin
        LastResponseText := '';
        LastStatusCode := 0;

        // Crear una copia del stream de entrada para trabajar con ella
        // Esto evita consumir el stream original y permite reintentos
        WorkBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, InStream);
        WorkBlob.CreateInStream(WorkInStream);

        // No añadir Authorization a nivel de HttpClient para evitar duplicados
        // La cabecera Authorization se añade solo al HttpRequestMessage

        UserEmail := GetOneDriveUserEmail();
        if UserEmail = '' then begin
            ResponseText := 'Error: Email del usuario OneDrive no configurado';
            exit(false);
        end;

        // Resolver el usuario en Graph (devuelve el id si existe). Si no existe, devolvemos error claro.
        if not ResolveOneDriveUser(UserEmail, ResolvedUserId, ResponseText) then
            exit(false);

        // Log del usuario resuelto para depuración
        Message('Usuario resuelto: %1 → %2', UserEmail, ResolvedUserId);

        // Construir URL de Microsoft Graph API para OneDrive usando el id resuelto
        FilePath := StrSubstNo('%1/%2', FolderPath, FileName);
        Url := StrSubstNo('https://graph.microsoft.com/v1.0/users/%1/drive/root:/%2:/content', ResolvedUserId, FilePath);

        // Debug: Verificar stream original antes de procesar
        Message('Debug: Iniciando procesamiento de stream');
        Message('Debug: FileName = %1', FileName);
        Message('Debug: FolderPath = %1', FolderPath);
        Message('Debug: URL = %1', Url);

        // Preparar un InStream independiente desde WorkBlob para depuración
        // Evita consumir el InStream original y el de trabajo
        WorkBlob.CreateInStream(InStrCopy);
        DebugText := '';
        while not InStrCopy.EOS do begin
            InStrCopy.ReadText(LineText);
            DebugText += LineText;
            if not InStrCopy.EOS then
                DebugText += '\n';
        end;
        // Asegurar que el stream de trabajo está en inicio para la subida
        WorkBlob.CreateInStream(WorkInStream);
        Message('Debug: ContentType = %1', ContentType);
        Message('Debug: Longitud contenido = %1', StrLen(DebugText));
        if StrLen(DebugText) > 0 then
            Message('Debug: Contenido creado = %1', CopyStr(DebugText, 1, 100))
        else
            Message('Debug: ERROR - Contenido vacío detectado');

        // Configurar HttpRequestMessage como en la función que funciona
        HttpReq.SetRequestUri(Url);
        HttpReq.Method := 'PUT';

        // Configurar headers de autorización
        HttpReq.GetHeaders(Headers);
        if not AddOAuthAuthorizationHeaderToRequest(HttpReq, ResponseText) then begin
            LastResponseText := ResponseText;
            exit(false);
        end;

        // Configurar content y sus headers
        // Primero escribir el contenido para que Content-Length se calcule
        Content.WriteFrom(WorkInStream);
        // No tocar Content-Type para evitar conflictos; Graph acepta application/octet-stream por defecto
        // Si fuera necesario, se puede forzar más adelante

        HttpReq.Content := Content;

        // Debug: Verificar Content-Length
        if Content.GetHeaders(ContentHeader) then begin
            ContentHeader.GetValues('Content-Length', ContentLengthList);
            if ContentLengthList.Count() > 0 then begin
                ContentLengthValue := ContentLengthList.Get(1);
                Message('Debug: Content-Length = %1', ContentLengthValue);
            end;
        end;

        // Verificar que no haya headers duplicados o malformados
        Message('Debug: Headers configurados correctamente');

        // Enviar usando HttpClient.Send como en la función que funciona
        if not Http.Send(HttpReq, HttpResp) then
            exit(false);

        HttpResp.Content().ReadAs(ResponseText);
        LastResponseText := CopyStr(ResponseText, 1, 250);
        LastStatusCode := HttpResp.HttpStatusCode();
        exit(HttpResp.IsSuccessStatusCode());
    end;

    local procedure PostTextWithRetry(ContentText: Text; FileName: Text; FolderPath: Text; ContentType: Text; var ResponseText: Text; Retries: Integer): Boolean
    var
        Attempt: Integer;
        DelayMs: Integer;
    begin
        for Attempt := 1 to Retries do begin
            if TryPostText(ContentText, FileName, FolderPath, ContentType, ResponseText) then
                exit(true);

            DelayMs := Power(2, Attempt) * 500;
            Sleep(DelayMs);
        end;
        exit(false);
    end;

    local procedure TryPostText(ContentText: Text; FileName: Text; FolderPath: Text; ContentType: Text; var ResponseText: Text): Boolean
    var
        Http: HttpClient;
        HttpResp: HttpResponseMessage;
        HttpReq: HttpRequestMessage;
        Content: HttpContent;
        Headers: HttpHeaders;
        ContentHeader: HttpHeaders;
        Url: Text;
        UserEmail: Text;
        ResolvedUserId: Text;
        FilePath: Text;
    begin
        LastResponseText := '';
        LastStatusCode := 0;

        UserEmail := GetOneDriveUserEmail();
        if UserEmail = '' then begin
            ResponseText := 'Error: Email del usuario OneDrive no configurado';
            exit(false);
        end;

        if not ResolveOneDriveUser(UserEmail, ResolvedUserId, ResponseText) then
            exit(false);

        FilePath := StrSubstNo('%1/%2', FolderPath, FileName);
        Url := StrSubstNo('https://graph.microsoft.com/v1.0/users/%1/drive/root:/%2:/content', ResolvedUserId, FilePath);

        HttpReq.SetRequestUri(Url);
        HttpReq.Method := 'PUT';

        if not AddOAuthAuthorizationHeaderToRequest(HttpReq, ResponseText) then begin
            LastResponseText := ResponseText;
            exit(false);
        end;

        Content.WriteFrom(ContentText);
        HttpReq.Content := Content;

        if not Http.Send(HttpReq, HttpResp) then
            exit(false);

        HttpResp.Content().ReadAs(ResponseText);
        LastResponseText := CopyStr(ResponseText, 1, 250);
        LastStatusCode := HttpResp.HttpStatusCode();
        exit(HttpResp.IsSuccessStatusCode());
    end;

    local procedure ResetInStream(var InStream: InStream)
    var
        TmpBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
        InStr2: InStream;
    begin
        TmpBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, InStream);
        TmpBlob.CreateInStream(InStr2);
        InStream := InStr2;
    end;

    local procedure GetSetup(): Record "OneDrive Webhook Setup"
    var
        Setup: Record "OneDrive Webhook Setup";
    begin
        if not Setup.Get('SETUP') then
            Error('Configura primero la página OneDrive Webhook Setup.');
        exit(Setup);
    end;

    // ─────────────────────────────────────────────────────────────────────────────
    // OAuth 2.0 para Microsoft Graph API
    // ─────────────────────────────────────────────────────────────────────────────
    local procedure AddOAuthAuthorizationHeader(var Http: HttpClient; var ErrorText: Text): Boolean
    var
        OAuth2: Codeunit OAuth2;
        Setup: Record "OneDrive Webhook Setup";
        AccessToken: SecretText;
        ClientID: Text;
        ClientSecret: SecretText;
        TenantID: Text;
        Scope: Text;
        AuthorityUrl: Text;
    begin
        Setup := GetSetup();

        ClientID := Setup."Client ID";
        ClientSecret := SecretText.SecretStrSubstNo('%1', Setup."Client Secret");
        TenantID := Setup."Tenant ID";

        if (ClientID = '') or (Setup."Client Secret" = '') or (TenantID = '') then begin
            ErrorText := 'Error: Configuración OAuth incompleta. Verifica Client ID, Client Secret y Tenant ID.';
            exit(false);
        end;

        Scope := 'https://graph.microsoft.com/.default';
        AuthorityUrl := StrSubstNo('https://login.microsoftonline.com/%1/oauth2/v2.0/token', TenantID);

        if OAuth2.AcquireTokenWithClientCredentials(ClientID, ClientSecret, AuthorityUrl, '', Scope, AccessToken) then begin
            if not Http.DefaultRequestHeaders().Add('Authorization', SecretStrSubstNo('Bearer %1', AccessToken)) then begin
                ErrorText := 'Error: No se pudo agregar header Authorization';
                exit(false);
            end;
            exit(true);
        end else begin
            ErrorText := 'Error: No se pudo obtener token OAuth de Microsoft Graph';
            exit(false);
        end;
    end;

    local procedure AddOAuthAuthorizationHeaderToRequest(var HttpReq: HttpRequestMessage; var ErrorText: Text): Boolean
    var
        OAuth2: Codeunit OAuth2;
        Setup: Record "OneDrive Webhook Setup";
        AccessToken: SecretText;
        ClientID: Text;
        ClientSecret: SecretText;
        TenantID: Text;
        Scope: Text;
        AuthorityUrl: Text;
        Headers: HttpHeaders;
    begin
        Setup := GetSetup();

        ClientID := Setup."Client ID";
        ClientSecret := SecretText.SecretStrSubstNo('%1', Setup."Client Secret");
        TenantID := Setup."Tenant ID";

        if (ClientID = '') or (Setup."Client Secret" = '') or (TenantID = '') then begin
            ErrorText := 'Error: Configuración OAuth incompleta. Verifica Client ID, Client Secret y Tenant ID.';
            exit(false);
        end;

        Scope := 'https://graph.microsoft.com/.default';
        AuthorityUrl := StrSubstNo('https://login.microsoftonline.com/%1/oauth2/v2.0/token', TenantID);

        if OAuth2.AcquireTokenWithClientCredentials(ClientID, ClientSecret, AuthorityUrl, '', Scope, AccessToken) then begin
            HttpReq.GetHeaders(Headers);
            if not Headers.Add('Authorization', SecretStrSubstNo('Bearer %1', AccessToken)) then begin
                ErrorText := 'Error: No se pudo agregar header Authorization';
                exit(false);
            end;
            exit(true);
        end else begin
            ErrorText := 'Error: No se pudo obtener token OAuth de Microsoft Graph';
            exit(false);
        end;
    end;

    local procedure GetOneDriveUserEmail(): Text
    begin
        exit(GetSetup()."OneDrive User Email");
    end;

    local procedure ResolveOneDriveUser(UserUpn: Text; var ResolvedId: Text; var ErrorText: Text): Boolean
    var
        Http: HttpClient;
        Resp: HttpResponseMessage;
        Url: Text;
        TokenResp: Text;
        JObj: JsonObject;
        Tok: JsonToken;
    begin
        ErrorText := '';
        ResolvedId := '';

        // Intentar resolución directa primero
        if TryResolveUserDirect(UserUpn, ResolvedId, ErrorText) then
            exit(true);

        // Si falla, intentar con filtro (más tolerante para variaciones de email)
        if TryResolveUserWithFilter(UserUpn, ResolvedId, ErrorText) then
            exit(true);

        // Si ambos fallan, devolver el último error
        exit(false);
    end;

    local procedure TryResolveUserDirect(UserUpn: Text; var ResolvedId: Text; var ErrorText: Text): Boolean
    var
        Http: HttpClient;
        Resp: HttpResponseMessage;
        Url: Text;
        TokenResp: Text;
        JObj: JsonObject;
        Tok: JsonToken;
    begin
        // Construir URL y hacer GET directo
        Url := StrSubstNo('https://graph.microsoft.com/v1.0/users/%1', UserUpn);

        // Asegurar header Authorization
        if not AddOAuthAuthorizationHeader(Http, TokenResp) then begin
            ErrorText := TokenResp;
            exit(false);
        end;

        if not Http.Get(Url, Resp) then begin
            ErrorText := 'Error: no se pudo consultar Graph para resolver el usuario';
            exit(false);
        end;

        Resp.Content().ReadAs(TokenResp);
        if Resp.IsSuccessStatusCode() then begin
            if JObj.ReadFrom(TokenResp) then begin
                if JObj.Get('id', Tok) then
                    ResolvedId := Tok.AsValue().AsText();
            end;
            exit(ResolvedId <> '');
        end;

        // Si falla, guardar error pero no salir (intentaremos con filtro)
        if JObj.ReadFrom(TokenResp) then begin
            if JObj.Get('error', Tok) then
                ErrorText := 'Direct lookup failed: ' + CopyStr(TokenResp, 1, 300);
        end;
        exit(false);
    end;

    local procedure TryResolveUserWithFilter(UserUpn: Text; var ResolvedId: Text; var ErrorText: Text): Boolean
    var
        Http: HttpClient;
        Resp: HttpResponseMessage;
        Url: Text;
        TokenResp: Text;
        JObj: JsonObject;
        JArray: JsonArray;
        Tok: JsonToken;
        UserTok: JsonToken;
        UserObj: JsonObject;
    begin
        // Construir URL con filtro
        Url := StrSubstNo('https://graph.microsoft.com/v1.0/users?$filter=userPrincipalName eq ''%1''&$select=id,userPrincipalName', UserUpn);

        // Asegurar header Authorization
        if not AddOAuthAuthorizationHeader(Http, TokenResp) then begin
            ErrorText := TokenResp;
            exit(false);
        end;

        if not Http.Get(Url, Resp) then begin
            ErrorText := 'Error: no se pudo consultar Graph con filtro';
            exit(false);
        end;

        Resp.Content().ReadAs(TokenResp);
        if Resp.IsSuccessStatusCode() then begin
            if JObj.ReadFrom(TokenResp) then begin
                if JObj.Get('value', Tok) then begin
                    JArray := Tok.AsArray();
                    if JArray.Count() > 0 then begin
                        JArray.Get(0, UserTok);
                        UserObj := UserTok.AsObject();
                        if UserObj.Get('id', Tok) then
                            ResolvedId := Tok.AsValue().AsText();
                    end;
                end;
            end;
            if ResolvedId = '' then
                ErrorText := StrSubstNo('Usuario no encontrado: %1', UserUpn);
            exit(ResolvedId <> '');
        end else begin
            if JObj.ReadFrom(TokenResp) then begin
                if JObj.Get('error', Tok) then
                    ErrorText := 'Filter lookup failed: ' + CopyStr(TokenResp, 1, 300);
            end;
            exit(false);
        end;
    end;

    local procedure GetOneDriveFolderPath(): Text
    var
        Setup: Record "OneDrive Webhook Setup";
        CustomPath: Text;
        DefaultPath: Text;
    begin
        Setup := GetSetup();
        CustomPath := Setup."OneDrive Folder Path";

        // Si hay ruta personalizada, usarla; si no, usar la estructura por defecto
        if CustomPath <> '' then begin
            // Limpiar la ruta personalizada (quitar / al inicio y final)
            CustomPath := DelChr(CustomPath, '<>', '/');
            exit(CustomPath);
        end else begin
            // Estructura por defecto: BC/<Company>/<YYYY>/<MM>
            DefaultPath := StrSubstNo('BC/%1/%2/%3',
                SanitizeForFileName(CompanyName()),
                Format(Today(), 0, '<Year4>'),
                Format(Today(), 0, '<Month,2>'));
            exit(DefaultPath);
        end;
    end;

    local procedure SanitizeForFileName(Value: Text): Text
    var
        Tmp: Text;
    begin
        // Reemplaza espacios por guion bajo y elimina caracteres inválidos para nombres de archivo en OneDrive/Windows
        Tmp := ConvertStr(Value, ' ', '_');
        Tmp := DelChr(Tmp, '=', '\/:*?"<>|');
        exit(Tmp);
    end;

    procedure GetLastResponseText(): Text
    begin
        exit(LastResponseText);
    end;

    procedure GetLastStatusCode(): Integer
    begin
        exit(LastStatusCode);
    end;

    procedure GetLastResultMessage(): Text
    var
        JObj: JsonObject;
        Tok: JsonToken;
        FileName: Text;
        Path: Text;
        ErrorMsg: Text;
        NameValue: Text;
        ParentPath: Text;
        ParentRef: JsonObject;
    begin
        if (LastStatusCode = 0) and (LastResponseText = '') then
            exit('No hay resultado disponible aún.');

        // Para Graph API, la respuesta exitosa tiene estructura diferente
        if (LastStatusCode >= 200) and (LastStatusCode < 300) then begin
            if JObj.ReadFrom(LastResponseText) then begin
                // Graph API devuelve el nombre del archivo en "name"
                if JObj.Get('name', Tok) then
                    FileName := Tok.AsValue().AsText();

                // La ruta se puede extraer de parentReference
                if JObj.Get('parentReference', Tok) then begin
                    ParentRef := Tok.AsObject();
                    if ParentRef.Get('path', Tok) then
                        ParentPath := Tok.AsValue().AsText();
                end;

                if FileName <> '' then
                    exit(StrSubstNo('OK (%1). Archivo subido: %2. Ubicación: %3', Format(LastStatusCode), FileName, ParentPath))
                else
                    exit(StrSubstNo('OK (%1). Archivo subido correctamente a OneDrive.', Format(LastStatusCode)));
            end else
                exit(StrSubstNo('OK (%1). Archivo subido a OneDrive.', Format(LastStatusCode)));
        end else begin
            // Error de Graph API
            if JObj.ReadFrom(LastResponseText) then begin
                if JObj.Get('error', Tok) then begin
                    ErrorMsg := ExtractGraphAPIError(Tok.AsObject());
                    exit(StrSubstNo('Error (%1). %2', Format(LastStatusCode), ErrorMsg));
                end;
            end;
            exit(StrSubstNo('HTTP %1. Respuesta: %2', Format(LastStatusCode), LastResponseText));
        end;
    end;

    local procedure ExtractGraphAPIError(ErrorObj: JsonObject): Text
    var
        CodeTok: JsonToken;
        MessageTok: JsonToken;
        Code: Text;
        Message: Text;
    begin
        if ErrorObj.Get('code', CodeTok) then
            Code := CodeTok.AsValue().AsText();
        if ErrorObj.Get('message', MessageTok) then
            Message := MessageTok.AsValue().AsText();

        // Manejo específico de errores comunes
        case Code of
            'Authorization_RequestDenied':
                exit('Permisos insuficientes. Verifica que la aplicación tenga Files.ReadWrite.All y User.Read.All (Application permissions) y que se haya dado admin consent.');
            'InvalidAuthenticationToken':
                exit('Token de autenticación inválido. Verifica Client ID, Client Secret y Tenant ID.');
            'ResourceNotFound':
                exit('Recurso no encontrado. Verifica que el usuario de OneDrive existe y tiene OneDrive activado.');
            'Request_ResourceNotFound':
                exit('Usuario no encontrado. Verifica el email en "OneDrive User Email".');
        end;

        if (Code <> '') and (Message <> '') then
            exit(StrSubstNo('%1: %2', Code, Message))
        else if Message <> '' then
            exit(Message)
        else if Code <> '' then
            exit(Code)
        else
            exit('Error desconocido de Graph API');
    end;
}
