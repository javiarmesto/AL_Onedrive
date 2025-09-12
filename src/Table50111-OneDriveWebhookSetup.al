table 50511 "OneDrive Webhook Setup"
{
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[20])
        {
            DataClassification = SystemMetadata;
        }
        field(30; "Tenant ID"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(40; "Client ID"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(50; "Client Secret"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(60; "OneDrive User Email"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(70; "OneDrive Folder Path"; Text[250])
        {
            DataClassification = CustomerContent;
        }
        field(80; "TXT Content"; Text[2048])
        {
            DataClassification = CustomerContent;
            Caption = 'TXT Content';
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }
}
