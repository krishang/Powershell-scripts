<#
.SYNOPSIS
    Exports a SQL Server database schema for documentation and analysis.

.DESCRIPTION
    Creates a ZIP containing:
      - Individual DDL files for tables, views, stored procedures, functions,
        triggers, synonyms, sequences, user-defined types, XML schema collections,
        partition functions/schemes, and database DDL triggers where supported by SMO.
      - CSV catalogues for objects, schemas, columns, keys, foreign keys, indexes,
        constraints, parameters, dependencies, triggers, synonyms, permissions,
        extended properties, and row counts.
      - JSON manifest and database metadata.
      - A combined schema SQL file.

    No table data is exported. Passwords, credentials, certificates, symmetric keys,
    asymmetric keys, database master keys, and linked-server secrets are not scripted.

.NOTES
    Author: Krishan Gurusinghe
    Version: 1.0.5

    PURPOSE
    -------
    Creates a schema-only export for documentation and analysis. No table row data is exported.

    PREREQUISITES
    -------------
    - Windows PowerShell 5.1+ or PowerShell 7+.
    - Network access from this computer to the target SQL Server.
    - A SQL login or Windows account that can connect to the database and view metadata.
    - SQL Server Management Objects (SMO), normally supplied by the SqlServer PowerShell module.

    FIRST-TIME SETUP / TROUBLESHOOTING
    ----------------------------------
    1. Optional connectivity test if SQL Server listens on TCP 1433:

           Test-NetConnection sqlserver.example.com -Port 1433

       A named instance or server using a different/static port may require its actual port instead.

    2. If PowerShell says this downloaded script is not digitally signed:

           Unblock-File .\Export-SqlDatabaseStructure-v1.0.5.ps1

       Inspect active execution policies with:

           Get-ExecutionPolicy -List

       If policy is not centrally enforced and a temporary process-only bypass is appropriate:

           Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

       The process-scoped setting ends when that PowerShell process closes. Do not override an
       organisation-enforced MachinePolicy or UserPolicy.

    3. If SMO cannot be loaded, install the SqlServer module for the current user:

           Install-Module SqlServer -Scope CurrentUser

       Or from an elevated PowerShell session for all users:

           Install-Module SqlServer -Scope AllUsers

       If prompted for NuGet or PSGallery trust, review the prompt and proceed only if permitted by
       organisational policy.

       Verify module/SMO loading:

           Import-Module SqlServer
           Get-Module SqlServer
           [Microsoft.SqlServer.Management.Smo.Server]

       Useful diagnostics if installation/loading fails:

           $PSVersionTable
           Get-Module SqlServer -ListAvailable
           Get-PSRepository

    4. Normal run using Windows integrated authentication:

           .\Export-SqlDatabaseStructure-v1.0.5.ps1 `
               -ServerInstance "sqlserver.example.com" `
               -Database "MyDatabase" `
               -OutputPath "C:\Temp\DatabaseSchema"

    5. Optional fuller export including database permissions and approximate row counts:

           .\Export-SqlDatabaseStructure-v1.0.5.ps1 `
               -ServerInstance "sqlserver.example.com" `
               -Database "MyDatabase" `
               -OutputPath "C:\Temp\DatabaseSchema" `
               -IncludePermissions `
               -IncludeRowCounts

    6. SQL authentication is supported when required:

           $cred = Get-Credential
           .\Export-SqlDatabaseStructure-v1.0.5.ps1 `
               -ServerInstance "sqlserver.example.com" `
               -Database "MyDatabase" `
               -OutputPath "C:\Temp\DatabaseSchema" `
               -Credential $cred

    EXPECTED WARNINGS
    -----------------
    SQL modules created WITH ENCRYPTION cannot expose their source definition. SMO can therefore report
    that an encrypted stored procedure or function cannot be scripted because its data is not accessible.
    This is expected. The exporter records that object as failed/inaccessible and continues.

    Check whether a module is encrypted with:

        SELECT
            s.name AS SchemaName,
            o.name AS ObjectName,
            o.type_desc AS ObjectType,
            OBJECTPROPERTY(o.object_id, 'IsEncrypted') AS IsEncrypted,
            CASE WHEN sm.definition IS NULL THEN 0 ELSE 1 END AS DefinitionFound
        FROM sys.objects AS o
        INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        LEFT JOIN sys.sql_modules AS sm ON sm.object_id = o.object_id
        WHERE o.name = N'ObjectName';

    SECURITY
    --------
    The exporter intentionally exports no table row data, passwords, connection secrets, encryption keys,
    certificate private material, or linked-server passwords. SQL module source can still contain comments,
    internal server names, network paths, email addresses, URLs, endpoints, and other hard-coded literals.
    Review generated SQL before sharing it outside the authorised environment.


.EXAMPLE
    .\Export-SqlDatabaseStructure-v1.0.5.ps1 `
        -ServerInstance "sqlserver.example.com" `
        -Database "MyDatabase" `
        -OutputPath "C:\Temp\DatabaseSchema"

.EXAMPLE
    $cred = Get-Credential
    .\Export-SqlDatabaseStructure-v1.0.5.ps1 `
        -ServerInstance "sqlserver,1433" `
        -Database "MyDatabase" `
        -OutputPath "C:\Temp\DbSchema" `
        -Credential $cred `
        -EncryptConnection
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerInstance,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Database,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [switch]$EncryptConnection,

    [Parameter()]
    [switch]$TrustServerCertificate,

    [Parameter()]
    [switch]$IncludeSystemObjects,

    [Parameter()]
    [switch]$IncludePermissions,

    [Parameter()]
    [switch]$IncludeRowCounts,

    [Parameter()]
    [switch]$Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor Cyan
}

function Get-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($c in $invalid) { $safe = $safe.Replace([string]$c, '_') }
    $safe = $safe.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safe)) { return '_' }
    if ($safe.Length -gt 180) { $safe = $safe.Substring(0, 180) }
    return $safe
}

function Quote-SqlName {
    param([AllowEmptyString()][string]$Name)
    return '[' + $Name.Replace(']', ']]') + ']'
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

function Load-Smo {
    Write-Step 'Loading SQL Server Management Objects (SMO)'
    try {
        Import-Module SqlServer -ErrorAction Stop
        return
    }
    catch {
        $assemblies = @(
            'Microsoft.SqlServer.ConnectionInfo',
            'Microsoft.SqlServer.Smo',
            'Microsoft.SqlServer.SmoExtended',
            'Microsoft.SqlServer.SqlEnum'
        )
        try {
            foreach ($assembly in $assemblies) {
                [void][Reflection.Assembly]::LoadWithPartialName($assembly)
            }
            if (-not ('Microsoft.SqlServer.Management.Smo.Server' -as [type])) {
                throw 'SMO Server type was not loaded.'
            }
            return
        }
        catch {
            throw @"
SQL Server SMO could not be loaded.
Install the SqlServer PowerShell module in an elevated PowerShell session:
    Install-Module SqlServer -Scope AllUsers
or for only your account:
    Install-Module SqlServer -Scope CurrentUser
Original error: $($_.Exception.Message)
"@
        }
    }
}

function New-ServerConnection {
    param(
        [string]$Instance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [bool]$Encrypt,
        [bool]$TrustCertificate
    )
    $connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
    $connection.ServerInstance = $Instance
    if ($SqlCredential) {
        $connection.LoginSecure = $false
        $connection.Login = $SqlCredential.UserName
        $connection.SecurePassword = $SqlCredential.Password
    }
    else {
        $connection.LoginSecure = $true
    }
    $connection.StatementTimeout = 0
    $connection.ConnectTimeout = 30

    # These properties vary between SMO versions, so set only when available.
    if ($connection.PSObject.Properties.Name -contains 'EncryptConnection') {
        $connection.EncryptConnection = $Encrypt
    }
    if ($connection.PSObject.Properties.Name -contains 'TrustServerCertificate') {
        $connection.TrustServerCertificate = $TrustCertificate
    }
    return $connection
}

function New-DbConnection {
    param(
        [string]$Instance,
        [string]$DbName,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [bool]$Encrypt,
        [bool]$TrustCertificate
    )
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $Instance
    $builder['Initial Catalog'] = $DbName
    $builder['Application Name'] = 'Database Structure Exporter'
    $builder['Connect Timeout'] = 30
    $builder['Encrypt'] = $Encrypt
    $builder['TrustServerCertificate'] = $TrustCertificate
    if ($SqlCredential) {
        $builder['Integrated Security'] = $false
        $builder['User ID'] = $SqlCredential.UserName
        $builder['Password'] = $SqlCredential.GetNetworkCredential().Password
    }
    else {
        $builder['Integrated Security'] = $true
    }
    return New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
}

function Invoke-DataTable {
    param(
        [Parameter(Mandatory)][System.Data.SqlClient.SqlConnection]$Connection,
        [Parameter(Mandatory)][string]$Query
    )
    $command = $Connection.CreateCommand()
    $command.CommandText = $Query
    $command.CommandTimeout = 0
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
    $table = New-Object System.Data.DataTable
    [void]$adapter.Fill($table)
    $command.Dispose()
    $adapter.Dispose()
    return ,$table
}

function Export-QueryCsv {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Name,
        [string]$Query,
        [string]$Folder
    )
    Write-Step "Exporting metadata: $Name"
    $dt = Invoke-DataTable -Connection $Connection -Query $Query
    $path = Join-Path $Folder ($Name + '.csv')
    if ($dt.Rows.Count -eq 0) {
        Set-Content -LiteralPath $path -Value '' -Encoding UTF8
    }
    else {
        $dt | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    }
    return $dt.Rows.Count
}

function Set-ScriptingOptions {
    param($Options)
    $Options.AnsiPadding = $true
    $Options.AppendToFile = $false
    $Options.Bindings = $true
    $Options.ClusteredIndexes = $true
    $Options.ContinueScriptingOnError = $false
    $Options.ConvertUserDefinedDataTypesToBaseType = $false
    $Options.DdlHeaderOnly = $false
    $Options.DdlBodyOnly = $false
    $Options.Default = $true
    $Options.DriAll = $true
    $Options.DriAllConstraints = $true
    $Options.DriAllKeys = $true
    $Options.DriChecks = $true
    $Options.DriDefaults = $true
    $Options.DriForeignKeys = $true
    $Options.DriPrimaryKey = $true
    $Options.DriUniqueKeys = $true
    $Options.ExtendedProperties = $true
    $Options.FullTextCatalogs = $true
    $Options.FullTextIndexes = $true
    $Options.IncludeDatabaseContext = $false
    $Options.IncludeDatabaseRoleMemberships = $false
    $Options.IncludeHeaders = $true
    $Options.IncludeIfNotExists = $false
    $Options.Indexes = $true
    $Options.NoCollation = $false
    $Options.NoCommandTerminator = $false
    $Options.NonClusteredIndexes = $true
    $Options.Permissions = [bool]$IncludePermissions
    $Options.SchemaQualify = $true
    $Options.SchemaQualifyForeignKeysReferences = $true
    $Options.ScriptBatchTerminator = $true
    $Options.ScriptData = $false
    $Options.ScriptDrops = $false
    $Options.ScriptOwner = $true
    $Options.ScriptSchema = $true
    $Options.Statistics = $true
    $Options.Triggers = $true
    $Options.WithDependencies = $false
    $Options.XmlIndexes = $true

    if ($Options.PSObject.Properties.Name -contains 'IncludeSystemNames') {
        $Options.IncludeSystemNames = $true
    }
    if ($Options.PSObject.Properties.Name -contains 'ScriptForCreateDrop') {
        $Options.ScriptForCreateDrop = $false
    }
}

function Get-ScriptText {
    param(
        [Parameter(Mandatory)]$SmoObject,
        [Parameter(Mandatory)]$Options
    )
    $lines = $SmoObject.Script($Options)
    if ($null -eq $lines -or $lines.Count -eq 0) { return '' }
    return (($lines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) + [Environment]::NewLine
}

function Export-SmoCollection {
    param(
        [Parameter(Mandatory)]$Collection,
        [Parameter(Mandatory)][string]$ObjectType,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)]$Options,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Index,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$CombinedScripts,
        [switch]$HasSchema,
        [switch]$SkipSystem
    )
    Ensure-Directory $Folder
    foreach ($obj in $Collection) {
        try {
            if ($SkipSystem -and -not $IncludeSystemObjects -and
                ($obj.PSObject.Properties.Name -contains 'IsSystemObject') -and $obj.IsSystemObject) {
                continue
            }
            $schemaName = if ($HasSchema -and ($obj.PSObject.Properties.Name -contains 'Schema')) { [string]$obj.Schema } else { '' }
            $baseName = if ($schemaName) { "$schemaName.$($obj.Name)" } else { [string]$obj.Name }
            $fileName = (Get-SafeFileName $baseName) + '.sql'
            $filePath = Join-Path $Folder $fileName
            $text = Get-ScriptText -SmoObject $obj -Options $Options
            $status = 'Exported'
            $notes = ''
            if ([string]::IsNullOrWhiteSpace($text)) {
                $status = 'No script returned'
                $notes = 'The object may be encrypted or unsupported by the installed SMO version.'
                $text = "-- No definition was returned for $ObjectType $baseName.`r`n-- It may be encrypted or unsupported by the installed SMO version.`r`n"
            }
            Set-Content -LiteralPath $filePath -Value $text -Encoding UTF8
            $CombinedScripts.Add("-- ============================================================================`r`n-- ${ObjectType}: $baseName`r`n-- ============================================================================`r`n$text`r`nGO`r`n")
            $Index.Add([pscustomobject]@{
                ObjectType = $ObjectType
                SchemaName = $schemaName
                ObjectName = [string]$obj.Name
                File = $filePath.Substring($script:ExportRoot.Length).TrimStart('\','/')
                Status = $status
                Notes = $notes
            })
        }
        catch {
            $Index.Add([pscustomobject]@{
                ObjectType = $ObjectType
                SchemaName = ''
                ObjectName = [string]$obj.Name
                File = ''
                Status = 'Error'
                Notes = $_.Exception.Message
            })
            Write-Warning "Failed to script $ObjectType $($obj.Name): $($_.Exception.Message)"
        }
    }
}

Load-Smo

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$exportName = (Get-SafeFileName $Database) + '_Structure_' + $timestamp
$script:ExportRoot = Join-Path $resolvedOutput $exportName
$zipPath = Join-Path $resolvedOutput ($exportName + '.zip')

if (Test-Path -LiteralPath $script:ExportRoot) {
    if (-not $Overwrite) { throw "Export folder already exists: $script:ExportRoot. Use -Overwrite to replace it." }
    Remove-Item -LiteralPath $script:ExportRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    if (-not $Overwrite) { throw "ZIP already exists: $zipPath. Use -Overwrite to replace it." }
    Remove-Item -LiteralPath $zipPath -Force
}
Ensure-Directory $resolvedOutput
Ensure-Directory $script:ExportRoot

$folders = @{
    Metadata = Join-Path $script:ExportRoot 'Metadata'
    Tables = Join-Path $script:ExportRoot 'Tables'
    Views = Join-Path $script:ExportRoot 'Views'
    Procedures = Join-Path $script:ExportRoot 'StoredProcedures'
    Functions = Join-Path $script:ExportRoot 'Functions'
    Triggers = Join-Path $script:ExportRoot 'Triggers'
    Synonyms = Join-Path $script:ExportRoot 'Synonyms'
    Sequences = Join-Path $script:ExportRoot 'Sequences'
    Types = Join-Path $script:ExportRoot 'UserDefinedTypes'
    XmlSchemas = Join-Path $script:ExportRoot 'XmlSchemaCollections'
    PartitionFunctions = Join-Path $script:ExportRoot 'PartitionFunctions'
    PartitionSchemes = Join-Path $script:ExportRoot 'PartitionSchemes'
}
$folders.Values | ForEach-Object { Ensure-Directory $_ }

$serverConnection = New-ServerConnection -Instance $ServerInstance -SqlCredential $Credential -Encrypt $EncryptConnection.IsPresent -TrustCertificate $TrustServerCertificate.IsPresent
$server = New-Object Microsoft.SqlServer.Management.Smo.Server($serverConnection)
$db = $server.Databases[$Database]
if ($null -eq $db) { throw "Database '$Database' was not found on '$ServerInstance'." }
$db.Refresh()

$sqlConnection = New-DbConnection -Instance $ServerInstance -DbName $Database -SqlCredential $Credential -Encrypt $EncryptConnection.IsPresent -TrustCertificate $TrustServerCertificate.IsPresent
$sqlConnection.Open()

try {
    Write-Step "Connected to $ServerInstance / $Database"

    $databaseInfoQuery = @"
SELECT
    @@SERVERNAME AS ServerName,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion,
    CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)) AS ProductLevel,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
    d.name AS DatabaseName,
    d.compatibility_level AS CompatibilityLevel,
    d.collation_name AS CollationName,
    d.recovery_model_desc AS RecoveryModel,
    d.containment_desc AS Containment,
    d.is_read_only AS IsReadOnly,
    d.is_auto_close_on AS IsAutoCloseOn,
    d.is_auto_shrink_on AS IsAutoShrinkOn,
    d.is_auto_create_stats_on AS IsAutoCreateStatsOn,
    d.is_auto_update_stats_on AS IsAutoUpdateStatsOn,
    d.snapshot_isolation_state_desc AS SnapshotIsolationState,
    d.is_read_committed_snapshot_on AS IsReadCommittedSnapshotOn,
    SYSDATETIMEOFFSET() AS ExportedAt
FROM sys.databases d
WHERE d.name = DB_NAME();
"@
    $dbInfo = Invoke-DataTable -Connection $sqlConnection -Query $databaseInfoQuery
    $dbInfo | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:ExportRoot 'DatabaseInfo.json') -Encoding UTF8

    $queries = [ordered]@{}
    $queries['Schemas'] = @"
SELECT s.schema_id AS SchemaId, s.name AS SchemaName, USER_NAME(s.principal_id) AS OwnerName
FROM sys.schemas s
WHERE s.name NOT IN ('sys','INFORMATION_SCHEMA')
ORDER BY s.name;
"@
    $queries['Objects'] = @"
SELECT s.name AS SchemaName, o.name AS ObjectName, o.type AS ObjectTypeCode,
       o.type_desc AS ObjectType, o.create_date AS CreateDate, o.modify_date AS ModifyDate,
       o.is_ms_shipped AS IsMicrosoftShipped,
       CASE WHEN sm.definition IS NULL AND o.type IN ('V','P','FN','IF','TF','TR') THEN 1 ELSE 0 END AS DefinitionUnavailable
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
LEFT JOIN sys.sql_modules sm ON sm.object_id = o.object_id
WHERE o.type NOT IN ('S','IT')
  AND ('$($IncludeSystemObjects.IsPresent)' = 'True' OR o.is_ms_shipped = 0)
ORDER BY s.name, o.type_desc, o.name;
"@
    $queries['Columns'] = @"
SELECT s.name AS SchemaName, o.name AS ObjectName, o.type_desc AS ObjectType,
       c.column_id AS ColumnId, c.name AS ColumnName,
       CASE WHEN t.is_user_defined = 1 THEN SCHEMA_NAME(t.schema_id) + '.' + t.name ELSE t.name END AS DataType,
       c.max_length AS MaxLengthBytes, c.precision AS [Precision], c.scale AS Scale,
       c.collation_name AS CollationName, c.is_nullable AS IsNullable,
       c.is_identity AS IsIdentity, ic.seed_value AS IdentitySeed, ic.increment_value AS IdentityIncrement,
       c.is_computed AS IsComputed, cc.definition AS ComputedDefinition, cc.is_persisted AS IsPersisted,
       dc.name AS DefaultConstraintName, dc.definition AS DefaultDefinition,
       c.is_rowguidcol AS IsRowGuid, c.is_sparse AS IsSparse, c.is_filestream AS IsFileStream,
       c.generated_always_type_desc AS GeneratedAlwaysType
FROM sys.columns c
JOIN sys.objects o ON o.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.types t ON t.user_type_id = c.user_type_id
LEFT JOIN sys.identity_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
LEFT JOIN sys.computed_columns cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
LEFT JOIN sys.default_constraints dc ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE o.type IN ('U','V','TF','IF')
  AND ('$($IncludeSystemObjects.IsPresent)' = 'True' OR o.is_ms_shipped = 0)
ORDER BY s.name, o.name, c.column_id;
"@
    $queries['Keys'] = @"
SELECT s.name AS SchemaName, t.name AS TableName, kc.name AS ConstraintName,
       kc.type_desc AS ConstraintType, i.name AS IndexName, ic.key_ordinal AS KeyOrdinal,
       c.name AS ColumnName, ic.is_descending_key AS IsDescending
FROM sys.key_constraints kc
JOIN sys.tables t ON t.object_id = kc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.indexes i ON i.object_id = kc.parent_object_id AND i.index_id = kc.unique_index_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE ('$($IncludeSystemObjects.IsPresent)' = 'True' OR t.is_ms_shipped = 0)
ORDER BY s.name, t.name, kc.name, ic.key_ordinal;
"@
    $queries['ForeignKeys'] = @"
SELECT fk.name AS ForeignKeyName,
       ps.name AS ParentSchema, pt.name AS ParentTable, pc.name AS ParentColumn,
       rs.name AS ReferencedSchema, rt.name AS ReferencedTable, rc.name AS ReferencedColumn,
       fkc.constraint_column_id AS ColumnOrdinal,
       fk.delete_referential_action_desc AS DeleteAction,
       fk.update_referential_action_desc AS UpdateAction,
       fk.is_disabled AS IsDisabled, fk.is_not_trusted AS IsNotTrusted,
       fk.is_not_for_replication AS IsNotForReplication
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.tables pt ON pt.object_id = fk.parent_object_id
JOIN sys.schemas ps ON ps.schema_id = pt.schema_id
JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
JOIN sys.tables rt ON rt.object_id = fk.referenced_object_id
JOIN sys.schemas rs ON rs.schema_id = rt.schema_id
JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
WHERE ('$($IncludeSystemObjects.IsPresent)' = 'True' OR pt.is_ms_shipped = 0)
ORDER BY ps.name, pt.name, fk.name, fkc.constraint_column_id;
"@
    $queries['Indexes'] = @"
SELECT s.name AS SchemaName, t.name AS TableName, i.name AS IndexName,
       i.type_desc AS IndexType, i.is_unique AS IsUnique, i.is_primary_key AS IsPrimaryKey,
       i.is_unique_constraint AS IsUniqueConstraint, i.has_filter AS HasFilter,
       i.filter_definition AS FilterDefinition, i.fill_factor AS [FillFactor],
       i.is_disabled AS IsDisabled, i.allow_row_locks AS AllowRowLocks,
       i.allow_page_locks AS AllowPageLocks,
       ic.key_ordinal AS KeyOrdinal, ic.is_included_column AS IsIncludedColumn,
       ic.is_descending_key AS IsDescending, c.name AS ColumnName,
       ds.name AS DataSpaceName
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
LEFT JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
LEFT JOIN sys.data_spaces ds ON ds.data_space_id = i.data_space_id
WHERE i.index_id > 0
  AND ('$($IncludeSystemObjects.IsPresent)' = 'True' OR t.is_ms_shipped = 0)
ORDER BY s.name, t.name, i.name, ic.is_included_column, ic.key_ordinal, ic.index_column_id;
"@
    $queries['CheckConstraints'] = @"
SELECT s.name AS SchemaName, t.name AS TableName, cc.name AS ConstraintName,
       cc.definition AS Definition, cc.is_disabled AS IsDisabled,
       cc.is_not_trusted AS IsNotTrusted, cc.is_not_for_replication AS IsNotForReplication
FROM sys.check_constraints cc
JOIN sys.tables t ON t.object_id = cc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE ('$($IncludeSystemObjects.IsPresent)' = 'True' OR t.is_ms_shipped = 0)
ORDER BY s.name, t.name, cc.name;
"@
    $queries['Parameters'] = @"
SELECT s.name AS SchemaName, o.name AS ObjectName, o.type_desc AS ObjectType,
       p.parameter_id AS ParameterId, p.name AS ParameterName,
       CASE WHEN ty.is_user_defined = 1 THEN SCHEMA_NAME(ty.schema_id) + '.' + ty.name ELSE ty.name END AS DataType,
       p.max_length AS MaxLengthBytes, p.precision AS [Precision], p.scale AS Scale,
       p.is_output AS IsOutput, p.has_default_value AS HasDefaultValue, p.default_value AS DefaultValue,
       p.is_readonly AS IsReadOnly, p.is_cursor_ref AS IsCursorReference
FROM sys.parameters p
JOIN sys.objects o ON o.object_id = p.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
JOIN sys.types ty ON ty.user_type_id = p.user_type_id
WHERE ('$($IncludeSystemObjects.IsPresent)' = 'True' OR o.is_ms_shipped = 0)
ORDER BY s.name, o.name, p.parameter_id;
"@
    $queries['Dependencies'] = @"
SELECT OBJECT_SCHEMA_NAME(d.referencing_id) AS ReferencingSchema,
       OBJECT_NAME(d.referencing_id) AS ReferencingObject,
       ro.type_desc AS ReferencingType,
       d.referenced_server_name AS ReferencedServer,
       d.referenced_database_name AS ReferencedDatabase,
       d.referenced_schema_name AS ReferencedSchema,
       d.referenced_entity_name AS ReferencedEntity,
       CASE WHEN d.referenced_id IS NOT NULL AND d.referenced_minor_id > 0
            THEN COL_NAME(d.referenced_id, d.referenced_minor_id)
       END AS ReferencedColumn,
       d.is_schema_bound_reference AS IsSchemaBound,
       d.is_ambiguous AS IsAmbiguous,
       d.referenced_id AS ReferencedObjectId
FROM sys.sql_expression_dependencies d
LEFT JOIN sys.objects ro ON ro.object_id = d.referencing_id
WHERE d.referencing_id IS NOT NULL
ORDER BY ReferencingSchema, ReferencingObject, ReferencedSchema, ReferencedEntity;
"@
    $queries['Triggers'] = @"
SELECT COALESCE(OBJECT_SCHEMA_NAME(tr.parent_id), SCHEMA_NAME(o.schema_id)) AS ParentSchema,
       CASE WHEN tr.parent_class_desc = 'DATABASE' THEN DB_NAME() ELSE OBJECT_NAME(tr.parent_id) END AS ParentObject,
       tr.name AS TriggerName, tr.parent_class_desc AS ParentClass,
       tr.is_instead_of_trigger AS IsInsteadOf, tr.is_disabled AS IsDisabled,
       tr.is_not_for_replication AS IsNotForReplication,
       te.type_desc AS TriggerEvent
FROM sys.triggers tr
LEFT JOIN sys.objects o ON o.object_id = tr.object_id
LEFT JOIN sys.trigger_events te ON te.object_id = tr.object_id
WHERE ('$($IncludeSystemObjects.IsPresent)' = 'True' OR tr.is_ms_shipped = 0)
ORDER BY ParentSchema, ParentObject, tr.name, te.type_desc;
"@
    $queries['Synonyms'] = @"
SELECT SCHEMA_NAME(schema_id) AS SchemaName, name AS SynonymName,
       base_object_name AS BaseObjectName, create_date AS CreateDate, modify_date AS ModifyDate
FROM sys.synonyms
ORDER BY SchemaName, SynonymName;
"@
    $queries['ExtendedProperties'] = @"
SELECT s.name AS SchemaName, o.name AS ObjectName, o.type_desc AS ObjectType,
       CASE ep.class
           WHEN 0 THEN 'DATABASE'
           WHEN 1 THEN CASE WHEN ep.minor_id = 0 THEN 'OBJECT' ELSE 'COLUMN' END
           WHEN 3 THEN 'SCHEMA'
           WHEN 6 THEN 'TYPE'
           WHEN 7 THEN 'INDEX'
           ELSE ep.class_desc
       END AS PropertyLevel,
       CASE WHEN ep.class = 1 AND ep.minor_id > 0 THEN COL_NAME(ep.major_id, ep.minor_id) END AS ColumnName,
       ep.name AS PropertyName, CONVERT(nvarchar(max), ep.value) AS PropertyValue
FROM sys.extended_properties ep
LEFT JOIN sys.objects o ON ep.class = 1 AND ep.major_id = o.object_id
LEFT JOIN sys.schemas s ON o.schema_id = s.schema_id
ORDER BY SchemaName, ObjectName, PropertyLevel, ColumnName, PropertyName;
"@
    $queries['DatabasePrincipals'] = @"
SELECT name AS PrincipalName, type_desc AS PrincipalType, authentication_type_desc AS AuthenticationType,
       default_schema_name AS DefaultSchema, create_date AS CreateDate, modify_date AS ModifyDate,
       is_fixed_role AS IsFixedRole
FROM sys.database_principals
WHERE principal_id > 4 AND name NOT IN ('guest','INFORMATION_SCHEMA','sys')
ORDER BY name;
"@
    $queries['RoleMemberships'] = @"
SELECT USER_NAME(rm.role_principal_id) AS RoleName,
       USER_NAME(rm.member_principal_id) AS MemberName
FROM sys.database_role_members rm
ORDER BY RoleName, MemberName;
"@
    $queries['Permissions'] = @"
SELECT USER_NAME(p.grantee_principal_id) AS Grantee,
       USER_NAME(p.grantor_principal_id) AS Grantor,
       p.state_desc AS PermissionState, p.permission_name AS PermissionName,
       p.class_desc AS PermissionClass,
       CASE p.class
           WHEN 0 THEN DB_NAME()
           WHEN 1 THEN QUOTENAME(OBJECT_SCHEMA_NAME(p.major_id)) + '.' + QUOTENAME(OBJECT_NAME(p.major_id))
           WHEN 3 THEN SCHEMA_NAME(p.major_id)
           WHEN 6 THEN TYPE_NAME(p.major_id)
           ELSE CONVERT(nvarchar(128), p.major_id)
       END AS SecuredObject,
       CASE WHEN p.class = 1 AND p.minor_id > 0 THEN COL_NAME(p.major_id, p.minor_id) END AS ColumnName
FROM sys.database_permissions p
ORDER BY Grantee, PermissionClass, SecuredObject, PermissionName;
"@
    if ($IncludeRowCounts) {
        $queries['TableRowCounts'] = @"
SELECT s.name AS SchemaName, t.name AS TableName, SUM(p.rows) AS ApproximateRowCount
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE ('$($IncludeSystemObjects.IsPresent)' = 'True' OR t.is_ms_shipped = 0)
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
"@
    }

    $metadataCounts = [ordered]@{}
    foreach ($item in $queries.GetEnumerator()) {
        if ($item.Key -eq 'Permissions' -and -not $IncludePermissions) { continue }
        $metadataCounts[$item.Key] = Export-QueryCsv -Connection $sqlConnection -Name $item.Key -Query $item.Value -Folder $folders.Metadata
    }

    $options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
    Set-ScriptingOptions -Options $options
    $index = New-Object 'System.Collections.Generic.List[object]'
    $combined = New-Object 'System.Collections.Generic.List[string]'

    Write-Step 'Scripting database objects'
    Export-SmoCollection -Collection $db.Tables -ObjectType 'Table' -Folder $folders.Tables -Options $options -Index $index -CombinedScripts $combined -HasSchema -SkipSystem
    Export-SmoCollection -Collection $db.Views -ObjectType 'View' -Folder $folders.Views -Options $options -Index $index -CombinedScripts $combined -HasSchema -SkipSystem
    Export-SmoCollection -Collection $db.StoredProcedures -ObjectType 'StoredProcedure' -Folder $folders.Procedures -Options $options -Index $index -CombinedScripts $combined -HasSchema -SkipSystem
    Export-SmoCollection -Collection $db.UserDefinedFunctions -ObjectType 'Function' -Folder $folders.Functions -Options $options -Index $index -CombinedScripts $combined -HasSchema -SkipSystem
    Export-SmoCollection -Collection $db.Synonyms -ObjectType 'Synonym' -Folder $folders.Synonyms -Options $options -Index $index -CombinedScripts $combined -HasSchema

    if ($db.PSObject.Properties.Name -contains 'Sequences') {
        Export-SmoCollection -Collection $db.Sequences -ObjectType 'Sequence' -Folder $folders.Sequences -Options $options -Index $index -CombinedScripts $combined -HasSchema
    }
    if ($db.PSObject.Properties.Name -contains 'UserDefinedDataTypes') {
        Export-SmoCollection -Collection $db.UserDefinedDataTypes -ObjectType 'UserDefinedDataType' -Folder $folders.Types -Options $options -Index $index -CombinedScripts $combined -HasSchema
    }
    if ($db.PSObject.Properties.Name -contains 'UserDefinedTableTypes') {
        Export-SmoCollection -Collection $db.UserDefinedTableTypes -ObjectType 'UserDefinedTableType' -Folder $folders.Types -Options $options -Index $index -CombinedScripts $combined -HasSchema
    }
    if ($db.PSObject.Properties.Name -contains 'XmlSchemaCollections') {
        Export-SmoCollection -Collection $db.XmlSchemaCollections -ObjectType 'XmlSchemaCollection' -Folder $folders.XmlSchemas -Options $options -Index $index -CombinedScripts $combined -HasSchema
    }
    if ($db.PSObject.Properties.Name -contains 'PartitionFunctions') {
        Export-SmoCollection -Collection $db.PartitionFunctions -ObjectType 'PartitionFunction' -Folder $folders.PartitionFunctions -Options $options -Index $index -CombinedScripts $combined
    }
    if ($db.PSObject.Properties.Name -contains 'PartitionSchemes') {
        Export-SmoCollection -Collection $db.PartitionSchemes -ObjectType 'PartitionScheme' -Folder $folders.PartitionSchemes -Options $options -Index $index -CombinedScripts $combined
    }
    if ($db.PSObject.Properties.Name -contains 'Triggers') {
        Export-SmoCollection -Collection $db.Triggers -ObjectType 'DatabaseTrigger' -Folder $folders.Triggers -Options $options -Index $index -CombinedScripts $combined -SkipSystem
    }

    # Object-level triggers are normally included with tables/views. Export separate copies for easier analysis.
    foreach ($table in $db.Tables) {
        if (-not $IncludeSystemObjects -and $table.IsSystemObject) { continue }
        foreach ($trigger in $table.Triggers) {
            Export-SmoCollection -Collection @($trigger) -ObjectType 'TableTrigger' -Folder $folders.Triggers -Options $options -Index $index -CombinedScripts $combined -HasSchema
        }
    }
    foreach ($view in $db.Views) {
        if (-not $IncludeSystemObjects -and $view.IsSystemObject) { continue }
        foreach ($trigger in $view.Triggers) {
            Export-SmoCollection -Collection @($trigger) -ObjectType 'ViewTrigger' -Folder $folders.Triggers -Options $options -Index $index -CombinedScripts $combined -HasSchema
        }
    }

    $index | Sort-Object ObjectType, SchemaName, ObjectName |
        Export-Csv -LiteralPath (Join-Path $script:ExportRoot 'ScriptedObjectIndex.csv') -NoTypeInformation -Encoding UTF8

    $combinedHeader = @"
/*
    Schema-only export
    Server: $ServerInstance
    Database: $Database
    Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
    IMPORTANT: This file contains no table data.
*/

USE $(Quote-SqlName $Database);
GO

"@
    Set-Content -LiteralPath (Join-Path $script:ExportRoot 'CombinedSchema.sql') -Value ($combinedHeader + ($combined -join [Environment]::NewLine)) -Encoding UTF8

    $manifest = [ordered]@{
        Exporter = 'Export-SqlDatabaseStructure-v1.0.5.ps1'
        ExporterVersion = '1.0.5'
        Author = 'Krishan Gurusinghe'
        GeneratedAt = (Get-Date).ToString('o')
        ServerInstance = $ServerInstance
        Database = $Database
        Authentication = if ($Credential) { 'SQL authentication' } else { 'Windows integrated authentication' }
        EncryptConnection = $EncryptConnection.IsPresent
        TrustServerCertificate = $TrustServerCertificate.IsPresent
        IncludeSystemObjects = $IncludeSystemObjects.IsPresent
        IncludePermissions = $IncludePermissions.IsPresent
        IncludeRowCounts = $IncludeRowCounts.IsPresent
        TableDataIncluded = $false
        OutputFolder = $script:ExportRoot
        ScriptedObjectCounts = @{}
        MetadataRowCounts = $metadataCounts
        Warnings = @(
            'Encrypted module definitions cannot be exported.',
            'Objects hidden by metadata permissions may be omitted.',
            'Server-level objects, SQL Agent jobs, linked servers, credentials, certificates, and secrets are intentionally excluded.',
            'The combined SQL file is intended for analysis and reference; individual scripts are the authoritative per-object output.'
        )
    }
    foreach ($group in ($index | Group-Object ObjectType)) {
        $manifest.ScriptedObjectCounts[$group.Name] = $group.Count
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:ExportRoot 'Manifest.json') -Encoding UTF8

    $readme = @"
DATABASE STRUCTURE EXPORT
=========================

Server: $ServerInstance
Database: $Database
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

CONTENTS
--------
- CombinedSchema.sql: Combined schema-only DDL for reference.
- ScriptedObjectIndex.csv: One row per scripted object with status and file path.
- DatabaseInfo.json: SQL Server and database settings.
- Manifest.json: Export options, warnings, and object counts.
- Metadata\*.csv: Machine-readable catalogues.
- Object folders: Individual SQL definitions.

SECURITY
--------
No table data was exported. No passwords, connection strings, private keys, certificate
material, credentials, or linked-server secrets were exported.

Before sharing, search the SQL files for environment-specific literals that may be embedded
inside custom stored procedures, functions, views, or triggers. Object definitions can contain
hard-coded server names, paths, email addresses, API endpoints, or comments entered by developers.

KNOWN LIMITATIONS
-----------------
- Encrypted SQL modules return no definition.
- Metadata not visible to the executing login is not exported.
- Server-level objects and SQL Agent objects are outside this database-only export.
- Cross-database dependencies are listed only where SQL Server records them in dependency metadata.
"@
    Set-Content -LiteralPath (Join-Path $script:ExportRoot 'README.txt') -Value $readme -Encoding UTF8

    Write-Step 'Creating ZIP archive'
    Compress-Archive -Path (Join-Path $script:ExportRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force

    Write-Host ''
    Write-Host 'Export completed successfully.' -ForegroundColor Green
    Write-Host "Folder: $script:ExportRoot"
    Write-Host "ZIP:    $zipPath"
    Write-Host "Objects indexed: $($index.Count)"
}
finally {
    if ($sqlConnection.State -ne [System.Data.ConnectionState]::Closed) { $sqlConnection.Close() }
    $sqlConnection.Dispose()
    if ($serverConnection) { $serverConnection.Disconnect() }
}
