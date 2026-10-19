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

[`Export-SqlDatabaseStructure-v1.0.5.ps1`](./Export-SqlDatabaseStructure-v1.0.5.ps1) creates a ZIP
package containing a schema-only SQL Server database export for documentation and analysis. It
includes individual DDL scripts for supported database objects, a combined schema script, a JSON
manifest, database metadata, and CSV catalogues for items such as columns, keys, indexes,
dependencies, permissions, and optional approximate table row counts.

The exporter does **not** export table rows or intentionally script passwords, credentials,
encryption keys, private certificate material, or linked-server secrets. SQL definitions can still
contain environment-specific literals; review the output before sharing it.

### Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- The `SqlServer` PowerShell module (provides SQL Server Management Objects, SMO)
- Network access and a SQL login or Windows account with permission to connect and view database metadata

Install the module for the current user if needed:

```powershell
Install-Module SqlServer -Scope CurrentUser
```

### Usage

Windows integrated authentication:

```powershell
.\Export-SqlDatabaseStructure-v1.0.5.ps1 `
    -ServerInstance "sqlserver.example.com" `
    -Database "MyDatabase" `
    -OutputPath "C:\Temp\DatabaseSchema"
```

SQL authentication prompts securely for credentials:

```powershell
$credential = Get-Credential
.\Export-SqlDatabaseStructure-v1.0.5.ps1 `
    -ServerInstance "sqlserver.example.com" `
    -Database "MyDatabase" `
    -OutputPath "C:\Temp\DatabaseSchema" `
    -Credential $credential
```

Optional switches:

- `-IncludePermissions` adds database permission metadata.
- `-IncludeRowCounts` adds approximate table row counts.
- `-IncludeSystemObjects` includes system objects where supported.
- `-EncryptConnection` enables connection encryption; `-TrustServerCertificate` is available for
  environments where certificate validation is deliberately bypassed.
- `-Overwrite` replaces an existing export folder or ZIP at the output path.

Encrypted SQL modules cannot expose their definitions, and metadata hidden from the connecting
account may be omitted. See the script's help text for troubleshooting and further details.
