page 50512 "OneDrive Webhook Setup"
{
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "OneDrive Webhook Setup";
    UsageCategory = Administration;
    Caption = 'OneDrive Webhook Setup';

    layout
    {
        area(content)
        {
            group("Graph API Configuration")
            {
                field("Tenant ID"; Rec."Tenant ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Azure AD Tenant ID para autenticación OAuth';
                }
                field("Client ID"; Rec."Client ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Application ID registrada en Entra ID';
                }
                field("Client Secret"; Rec."Client Secret")
                {
                    ApplicationArea = All;
                    ExtendedDatatype = Masked;
                    ToolTip = 'Client Secret de la aplicación registrada';
                }
                field("OneDrive User Email"; Rec."OneDrive User Email")
                {
                    ApplicationArea = All;
                    ToolTip = 'Email del usuario cuyo OneDrive se usará';
                }
                field("OneDrive Folder Path"; Rec."OneDrive Folder Path")
                {
                    ApplicationArea = All;
                    ToolTip = 'Ruta personalizada en OneDrive (ej: MisCarpetas/Exports). Si está vacío usa BC/{Company}/{YYYY}/{MM}';
                }
                field("Is Shared Folder"; Rec."Is Shared Folder")
                {
                    ApplicationArea = All;
                    ToolTip = 'Indica si la carpeta es compartida (requiere Drive ID e Item ID)';
                }
                field("Shared Folder Drive ID"; Rec."Shared Folder Drive ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Drive ID de la carpeta compartida (solo si es compartida)';
                }
                field("Shared Folder Item ID"; Rec."Shared Folder Item ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Item ID de la carpeta compartida (solo si es compartida)';
                }
                field("TXT Content"; Rec."TXT Content")
                {
                    ApplicationArea = All;
                    MultiLine = true;
                    ToolTip = 'Contenido que se usará para generar el archivo TXT de prueba.';
                }
            }
            // Legacy fields removed
        }
    }

    actions
    {
        area(Processing)
        {
            action(UploadTXTFromSetup)
            {
                Caption = 'Subir TXT con contenido de Setup';
                ApplicationArea = All;
                Image = Export;
                trigger OnAction()
                var
                    Orchestrator: Codeunit "TXT → Webhook Orchestrator";
                begin
                    EnsureInit();
                    Orchestrator.ExportTxtFromSetupField();
                    Message(Orchestrator.GetLastResultMessage());
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        EnsureInit();
    end;

    local procedure EnsureInit()
    begin
        if not Rec.Get('SETUP') then begin
            Rec.Init();
            Rec."Primary Key" := 'SETUP';
            // Populate with provided test credentials on first run (change if needed)
            Rec."Tenant ID" := 'efbe2e2d-0fe4-4bbc-9e68-9c68eb85bddc';
            Rec."Client ID" := 'e4a06571-17a9-4546-9caf-7f6642947148';
            Rec."Client Secret" := '1bP8Q~O6bqbgA_nZntOgazZPyPVE.Q12j.cCobZE';
            // Set a sensible default for OneDrive user — update to the target user's email
            Rec."OneDrive User Email" := 'javiarmesto@circeinnovation.eu';
            // Set test content for TXT upload
            Rec."TXT Content" := 'Hola Edu vamooos';
            Rec.Insert(true);
        end;
    end;
}
