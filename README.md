# Welcome to the Power shell scripts - 
 This repository contains some powershell scripts I have been working on in automating some of the network processors.
 
   *sFTPDownloadPS* - This script is used to download files from a sFTP share. Edit the file to enter the connection variables:
  - $source = "/";
  -  $FileTypes="*.csv";
  -  $destination= "C:\Download\CSV";
  - $sFTPServer="sftp.remoteServer.com";
  - $sFTPUser="sFTPUser";
  - $sFTPPassword="Password";
   
   If you wish to encrypt the password this could be done by running the 
   (get-credential).password | ConvertFrom-SecureString | set-content "C:\temp\password.txt"
   Note this can only be decrypted on the machine it was encryted with the exact user logins.
   
#### Create an encrytped password. Note can only be decrypted on the machine and user who created this.
#### (get-credential).password | ConvertFrom-SecureString | set-content "C:\temp\password.txt"
#### $sFTPPassword = Get-Content "C:\temp\password.txt" | ConvertTo-SecureString

## SQL Server database structure exporter

[`Export-SqlDatabaseStructure-v2.0.1.ps1`](./Export-SqlDatabaseStructure-v2.0.1.ps1) exports a
SQL Server database's schema for documentation, analysis, and AI-assisted database work. It
produces a technical export with individual DDL files, a combined schema script, CSV metadata
catalogues, a JSON manifest, and database information. By default it also creates a separate
Copilot-ready knowledge source with object-level Markdown, database overview and agent guidance.

The tool does **not** export table row data. It intentionally excludes passwords, credentials,
encryption keys, private certificate material, and linked-server secrets. Object definitions may
still contain environment-specific names, URLs, paths, comments, or hard-coded literals; review
the generated files before sharing them.

### Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- SQL Server Management Objects (SMO), normally provided by the `SqlServer` PowerShell module
- Network access and a SQL login or Windows account with permission to connect and view database metadata

Install the module for the current user if needed:

```powershell
Install-Module SqlServer -Scope CurrentUser
```

### Usage

Windows integrated authentication:

```powershell
.\Export-SqlDatabaseStructure-v2.0.1.ps1 `
    -ServerInstance "sqlserver.example.com" `
    -Database "MyDatabase" `
    -OutputPath "C:\Temp\DatabaseSchema"
```

SQL authentication prompts securely for credentials:

```powershell
$credential = Get-Credential
.\Export-SqlDatabaseStructure-v2.0.1.ps1 `
    -ServerInstance "sqlserver.example.com" `
    -Database "MyDatabase" `
    -OutputPath "C:\Temp\DatabaseSchema" `
    -Credential $credential
```

Optional switches:

- `-IncludePermissions` adds database permission metadata.
- `-IncludeRowCounts` adds approximate table row counts.
- `-IncludeSystemObjects` includes system objects where supported.
- `-SkipCopilotKnowledge` skips the Copilot-ready knowledge files and transfer archive.
- `-EncryptConnection` enables connection encryption. `-TrustServerCertificate` is available when
  certificate validation is deliberately bypassed.
- `-Overwrite` replaces existing output files.

### Output

The output path receives a timestamped export folder and a technical ZIP archive. Unless
`-SkipCopilotKnowledge` is specified, the folder also contains `CopilotKnowledge` and a separate
`_CopilotKnowledge.zip` transfer archive. The knowledge source includes per-object Markdown with
available columns, parameters, dependencies and definitions, plus CSV catalogues and guidance for
using the export as an AI knowledge source.

Encrypted SQL modules cannot expose their definitions, and objects hidden by metadata permissions
may be omitted. See the script's help text for troubleshooting, limitations, and security guidance.
