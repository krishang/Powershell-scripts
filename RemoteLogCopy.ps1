<#Author:KrishanG
  Date: 12/06/2020
  Prerequisite: Use the script “StoreSecurePass.ps1” to store your password securly on the server which this script will utilze.
                Update the location parameters in the main calling function.
  Rem:          Use this powershull script to copy iis log files from a remote host to a desired location.
                This copies the last updated log file and does not copy the entire lot. See the date function below.
                The idea is to set this as a stask schedular on a daily basis.

#>

function CopyLastLogs{
    param(
         [Parameter()]
            [string] $SourceLocation, 
         [Parameter()]  
            [string] $Destination, 
         [Parameter()]
            [string] $PassFile, 
         [Parameter()]
            [string] $Username
        )

    [string]$DriveLetter="J"
    
    $Password = Get-Content $PassFile | ConvertTo-SecureString
    $Credentials = New-Object System.Management.Automation.PSCredential $Username,$Password

    $MappedDrive = (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue)
   
    if($MappedDrive)
    {
    #Drive is mapped. Check to see if it mapped to the correct path
    if($MappedDrive.DisplayRoot -ne $SourceLocation)
    {
        # Drive Mapped to the incorrect path. Remove and readd:
        Remove-PSDrive -Name $DriveLetter
        New-PSDrive -Name $DriveLetter -Root $SourceLocation -Persist -PSProvider "FileSystem"
    }
    }
else
{
  #Drive is not mapped
    if (-not (Test-Path $SourceLocation ) )
    {
    New-PSDrive -Name $DriveLetter -PSProvider filesystem -Root $SourceLocation -Credential $Credentials
     }  

}

    $SourceFiles = get-childitem $SourceLocation
    
    # Get the log files and copy this over to the server log folder. I only want yesterday log files.
    $Date = Get-Date
    $Date = $Date.adddays(-1)
    $Date2Str = $Date.ToString("yyyMMdd")

    ForEach ($File in $SourceFiles){
        $FileDate = $File.creationtime
        $CTDate2Str = $FileDate.ToString("yyyyMMdd")
        if ($CTDate2Str -eq $Date2Str) {Copy-Item $File.Fullname $Destination}
    }
    
}

function Main 
{
    $SourceLocation = "\\192.x.x.x\c$\inetpub\logs\LogFiles\W3SVC1"
    $Destination="C:\\ServerLogCopy\\Server1\w3SVC1\"
    $PassFile = "C:\ServerLogCopy\password.txt"
    $Username = "administrator"
    
    # Copy the first log file from Server1 W3SVC1
    CopyLastLogs $SourceLocation $Destination $PassFile $Username
    
    # Copy the second Log file from Server2 W3SV2
    $SourceLocation = "\\192.x.x.x\c$\inetpub\logs\LogFiles\W3SVC2"
    $Destination="C:\\ServerLogCopy\\Server2\w3SVC2\"

    CopyLastLogs $SourceLocation $Destination $PassFile $Username

        
    # Now Run the log paser and insert the data into the SQL database "CopyLogToDB.PS1"

}

# call the main function. This is the entry point of executing the scripts.
Main
