// Test script to verify ExportTxtFromSetupField function
codeunit 50500 "Test TXT Upload"
{
    procedure TestExportTxtFromSetupField()
    var
        Orchestrator: Codeunit "TXT → Webhook Orchestrator";
        Setup: Record "OneDrive Webhook Setup";
    begin
        // Ensure setup record exists and has content
        if not Setup.Get('SETUP') then begin
            Setup.Init();
            Setup."Primary Key" := 'SETUP';
            Setup."TXT Content" := 'Hola Edu vamooos';
            Setup.Insert(true);
            Message('Setup record created with test content');
        end else begin
            // Update content if empty
            if Setup."TXT Content" = '' then begin
                Setup."TXT Content" := 'Hola Edu vamooos';
                Setup.Modify(true);
                Message('Setup TXT Content updated with test content');
            end;
        end;

        // Test the function
        Message('Starting test of ExportTxtFromSetupField...');
        Orchestrator.ExportTxtFromSetupField();
        Message('Test completed. Result: %1', Orchestrator.GetLastResultMessage());
    end;
}