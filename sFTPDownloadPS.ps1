# Author: KrishanG 
# Released under GNU license.
# Date : 25/07/2022
# Remarks: This script connects to the ICON SFTP server and downloads all the CSV files and also uploads all the scanned documents sitting on the docman folder.
# download and install using a power shell terminal
#        Install-Module -Name Posh-SSH
# if the script does not run check that the functions exist in the current version of Posh-SSH
# Show all available module commands
#Write-Host "Listing all Posh-SSH - Commands..." -ForegroundColor Green
#Get-Command -Module Posh-SSH
#########################################################################################################################
#Creating a folder to store files downloaded from the SFTP share

$source = "/";
$FileTypes="*.csv";
$destination= "C:\Download\CSV";
$sFTPServer="sftp.removeServer.com";
$sFTPUser="sFTPUser";
$sFTPPassword="Password";


Remove-Item $destination -Recurse;

# will be replaced with encryption later
# Create an encrytped password. Note can only be decrypted on the machin and user who created this.
# (get-credential).password | ConvertFrom-SecureString | set-content "C:\temp\password.txt"
# $sFTPPassword = Get-Content "C:\temp\password.txt" | ConvertTo-SecureString

# create the directory if this does not exist
New-item -itemtype directory -force -path $destination;

#Setting credentials for the user account

$password = ConvertTo-SecureString $sFTPPassword -AsPlainText -Force

$creds = New-Object System.Management.Automation.PSCredential ($sFTPUser, $password)

#Establishing an SFTP session

$Session = New-SFTPSession -Computername $sFTPServer  -credential $creds

#Downloading the csv files from the folder
Get-SFTPChildItem $session -Path $source -Recursive| ForEach-Object{
    if ($_.Fullname -like $FileTypes) 
    {  
        
        Get-SFTPItem -SessionId $session.SessionID -Path $_.Fullname   -Destination $destination 
    }

    write-output $_.FullName 

}

#Get-SFTPItem -SessionId $session.SessionID -Path $source  -Destination $destinationCSV

Remove-SFTPSession $session -Verbose
