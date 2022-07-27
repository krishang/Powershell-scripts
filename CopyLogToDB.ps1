 

function ImportLogFilesToDB
{
    param(
        [Parameter()]
        [string] $httpLogPath,
        [Parameter()]  
        [string] $connectionString,
        [Parameter()]  
        [string] $dbtable
        )
       


    If ([string]::IsNullOrEmpty($httpLogPath) -eq $true)
    {
        Throw "The log path must be specified."
    }
 
    [string] $logParser = "${env:ProgramFiles(x86)}" `
        + "\Log Parser 2.2\LogParser.exe "
 
    [string] $query = `
        [string] $query = `
        "SELECT" `
            + " LogFilename" `
            + ", RowNumber" `
            + ", TO_TIMESTAMP(date, time) AS EntryTime" `
            + ", s-ip AS sIp" `
            + ", cs-method AS csMethod" `
            + ", cs-uri-stem AS csUriStem" `
            + ", cs-uri-query AS csUriQuery" `
            + ", s-port AS sPort" `
            + ", TO_STRING(cs-username) AS csUsername" `
            + ", c-ip AS cIp" `
            + ", cs(User-Agent) AS csUserAgent" `
            + ", cs(Referer) AS csReferer" `
            + ", sc-status AS scStatus" `
            + ", sc-substatus AS scSubstatus" `
            + ", sc-win32-status AS scWin32Status" `
            + ", time-taken AS timeTaken" `
        + " INTO $dbtable" `
        + " FROM $httpLogPath"
 
    
 
    [string[]] $parameters = @()
 
    $parameters += $query
    $parameters += "-i:W3C"
    $parameters += "-e:-1"
    #$parameters += "-recurse:-1"
    $parameters += "-o:SQL"
    $parameters += "-createTable:ON"
    $parameters += "-oConnString:$connectionString"
 
    Write-Debug "Parameters: $parameters"
 
    Write-Host "Importing log files to database..." + $parameters
    & $logParser $parameters

   

}

function DeleteLogs([string]$httpLogPath)
{
    Write-Host "Wait 50 seconds until logPaser finishes reading all the logs"
    Start-Sleep -s 50
    Write-Host "Removing log files..."
    
    Remove-Item ($httpLogPath)


}

# Main program which runs the import function
function Main
{
    # Specify your connection string to DB
    [string] $connectionString = "Driver={SQL Server Native Client 11.0};" `
    + "Server=YourSQLServer;Database=WebServerLogs;Trusted_Connection=yes;"
    
  
    [string] $httpLogPath1 = "C:\ServerLogCopy\serenno\W3svc2\*.log"
    
    [string] $dbtable="WebServerW3SVC1"

     $dbtable="SerennoW3SVC2aug"
    ImportLogFilesToDB  $httpLogPath1 $connectionString $dbtable


<#
    DeleteLogs $httpLogPath1
    DeleteLogs $httpLogPath2

    DeleteLogs $httpLogPath3
#>
   
}

Main