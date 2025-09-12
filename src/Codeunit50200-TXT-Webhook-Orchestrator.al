codeunit 50510 "TXT → Webhook Orchestrator"
{
    SingleInstance = false;

    var
        LastResponseText: Text;
        LastStatusCode: Integer;

    // Variante: si quieres pasar el contenido desde fuera
    procedure ExportTxtContentToOneDrive(FileBaseName: Text; Content: Text)
    var
        FileName: Text;
        FolderPath: Text;
        Mime: Text;
        Resp: Text;
        Ok: Boolean;
    begin
        if FileBaseName = '' then
            FileBaseName := 'Export';
        FileName := StrSubstNo('%1_%2.txt', SanitizeForFileName(FileBaseName), SanitizeForFileName(Format(CurrentDateTime(), 0, 9)));

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
        if Content = '' then
            Error('El campo "TXT Content" en Setup está vacío.');
        ExportTxtContentToOneDrive('SetupTXT', Content);
    end;

    // ─────────────────────────────────────────────────────────────────────────────
    // HTTP: POST al webhook con Base64 + metadatos + header de secreto simple
    // ─────────────────────────────────────────────────────────────────────────────

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
        Req: HttpRequestMessage;
        Url: Text;
        TokenResp: Text;
        JObj: JsonObject;
        Tok: JsonToken;
    begin
        // Construir URL y hacer GET directo
        Url := StrSubstNo('https://graph.microsoft.com/v1.0/users/%1', UserUpn);

        Req.SetRequestUri(Url);
        Req.Method := 'GET';

        // Asegurar header Authorization
        if not AddOAuthAuthorizationHeaderToRequest(Req, TokenResp) then begin
            ErrorText := TokenResp;
            exit(false);
        end;

        if not Http.Send(Req, Resp) then begin
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
        Req: HttpRequestMessage;
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

        Req.SetRequestUri(Url);
        Req.Method := 'GET';

        // Asegurar header Authorization
        if not AddOAuthAuthorizationHeaderToRequest(Req, TokenResp) then begin
            ErrorText := TokenResp;
            exit(false);
        end;

        if not Http.Send(Req, Resp) then begin
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

    procedure GetLastResultMessage(): Text
    begin
        if (LastStatusCode >= 200) and (LastStatusCode < 300) then
            exit('Subida OK')
        else
            exit(StrSubstNo('Error HTTP %1', LastStatusCode));
    end;
}
