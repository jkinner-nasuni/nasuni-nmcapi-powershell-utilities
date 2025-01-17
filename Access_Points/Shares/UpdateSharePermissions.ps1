﻿#Update All Shares for a given Filer/Volume using the supplied CSV input file
#if more than one user or group are specified in a section, they should be divided by spaces. Use a single backslash for domain users an groups

#populate NMC hostname or IP address
$hostname = "InsertNMChostname"

#username for AD accounts supports both UPN (user@domain.com) and DOMAIN\\samaccountname formats (two backslashes required ). Nasuni Native user accounts are also supported.
$username = "InsertUsername"
$password = 'InsertPassword'

#provide the path to input CSV
$csvPath = "c:\export\ShareInfo.csv"

#end variables

#combine credentials for token request
$credentials = '{"username":"' + $username + '","password":"' + $password + '"}'

#Request token and build connection headers
#Allow untrusted SSL certs
if ($PSVersionTable.PSEdition -eq 'Core') #PowerShell Core
{
	if ($PSDefaultParameterValues.Contains('Invoke-RestMethod:SkipCertificateCheck')) {}
	else {
		$PSDefaultParameterValues.Add('Invoke-RestMethod:SkipCertificateCheck', $true)
	}
}
else #other versions of PowerShell
{if ("TrustAllCertsPolicy" -as [type]) {} else {		
	
Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
	public bool CheckValidationResult(
		ServicePoint srvPoint, X509Certificate certificate,
		WebRequest request, int certificateProblem) {
		return true;
	}
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName TrustAllCertsPolicy

#set the correct TLS Type
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
 } }

#build JSON headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Accept", 'application/json')
$headers.Add("Content-Type", 'application/json')

#construct Uri
$url="https://"+$hostname+"/api/v1.1/auth/login/"
 
#Use credentials to request and store a session token from NMC for later use
$result = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $credentials
$token = $result.token
$headers.Add("Authorization","Token " + $token)

#Begin share update

#read the contents of the CSV into variables, skipping the first line and replace semicolons to commas in share perms and set the right domain backslashes for domain json
$shares = Get-Content $csvPath | Select-Object -Skip 1 | ConvertFrom-Csv -Delimiter "," -header "ID","Volume_Guid","Filer_Serial","ShareName","Path","comment","block_files","fruit_enabled","AuthAll","ro_users","ro_groups","rw_users","rw_groups"
ForEach ($share in $shares) {
	$ID = $($share.ID)
	$volume_guid = $($share.volume_guid)
	$filer_serial = $($share.filer_serial)
	$AuthAll = $($share.AuthAll)
	if (!$Share.ro_users) {} else {$ROUsers = "'"+$($Share.ro_users)+"'" -replace '\\','\\' -replace ' ',''','''}
	if (!$Share.ro_groups) {} else {$ROGroups = "'"+$($Share.ro_groups)+"'" -replace '\\','\\' -replace ' ',''','''}
	if (!$Share.rw_users) {} else {$RWUsers = "'"+$($Share.rw_users)+"'" -replace '\\','\\' -replace ' ',''','''}
	if (!$Share.rw_groups) {} else {$RWGroups = "'"+$($Share.rw_groups)+"'" -replace '\\','\\' -replace ' ',''','''}
	if ($AuthAll -eq $false) {

	#build the body for share update
	$body = @"
	{
	"auth": {
	"authall": "FALSE",
	"ro_users": [$ROUsers],
	"ro_groups": [$ROGroups],
	"rw_users": [$RWUsers],
	"rw_groups": [$RWGroups]
	}
	}
"@

	$jsonbody = $body | ConvertFrom-Json | ConvertTo-Json

	#set up the URL for the create share NMC endpoint
	$url="https://"+$hostname+"/api/v1.1/volumes/" + $volume_guid + "/filers/" + $filer_serial + "/shares/"

	#update the share
	$urlID = $url+$ID+"/"
	$response=Invoke-RestMethod -Uri $urlID -Headers $headers -Method Patch -Body $jsonbody

	#write the response to the console
	write-output $response | ConvertTo-Json

	#remove variables for the next loop
	Remove-Variable Body
	Remove-Variable jsonbody
	Remove-Variable ROGroups
	Remove-Variable RWGroups
	Remove-Variable ROUsers
	Remove-Variable RWUsers

	#sleep before starting the next loop to avoid NMC API throttling
	Start-Sleep -s 1.1
}
}
