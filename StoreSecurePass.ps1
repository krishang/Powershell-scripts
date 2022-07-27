<#Author:KrishanG
  Date: 11/06/2020
  Rem: Use this powershull script to create a secure password file. This will encrpt the password and store this in the desired file.
#>

function CreateFile
{
  param(
         [Parameter()]
            [string] $PathAndFile, 
         [Parameter()]  
            [string] $PasswordToEncrypt
        )


$Password = $PasswordToEncrypt | ConvertTo-SecureString -AsPlainText -Force
$Password | ConvertFrom-SecureString | Out-File $PathAndFile

#Get the password and decrypt
$Password = Get-Content $File | ConvertTo-SecureString
Write-Output $Password
}

## entry point to the script. 
function Main
{
    $PathAndFile = "C:\ServerLogCopy\password.txt"
    $PasswordToEncrypt="yourPassword"
    CreateFile $PathAndFile $PasswordToEncrypt

}
# call run the function
Main