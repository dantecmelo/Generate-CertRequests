<#
.SYNOPSIS
    Generates and submits multiple certificate requests to an ADCS issuing CA for load testing,
    including performance metrics and error tracking.

.DESCRIPTION
    This script automates the creation of numerous certificate requests using a specified
    certificate template and submits them to the Active Directory Certificate Services (ADCS)
    issuing Certification Authority (CA). Each request will have a unique Common Name (CN)
    based on a GUID to avoid conflicts.

    It's intended for load testing the CA or for scenarios where many certificates are needed
    programmatically. This enhanced version tracks:
    - Total execution time.
    - Rate of successfully submitted certificates per second.
    - Number of errors encountered.
    - Details of each error.

    This version first generates all certificate request files (*.req) and then proceeds
    to submit them in a separate phase.

.PARAMETER CaServer
    The hostname or FQDN of the ADCS issuing CA server.
    Example: 'ca.contoso.com'

.PARAMETER CaName
    The issuing CA name.
    Example: 'Contoso Issuing CA'

.PARAMETER TemplateName
    The name of the certificate template to use for the requests.
    This template must exist on the specified CA and be configured for certificate requests.
    Example: 'WebServer' or 'Computer'

.PARAMETER NumberOfRequests
    The total number of certificate requests to generate and submit.
    Default: 10

.PARAMETER OutputDirectory
    The directory where the generated .req files will be saved.
    If the directory does not exist, the script will attempt to create it.
    Default: '.\CertRequests'

.EXAMPLE
    .\Generate-CertRequests.ps1 -CaServer "ca.example.com" -CaName "Contoso Issuing CA" -TemplateName "WebServer" -NumberOfRequests 10

.EXAMPLE
    .\Generate-CertRequests.ps1 -CaServer "yourca.local" -CaName "Contoso Issuing CA" -TemplateName "Computer" -NumberOfRequests 20 -OutputDirectory "C:\Temp\CertReqs"
    
.NOTES
    - Requires PowerShell 5.0 or higher.
    - Requires the CertificateServicesAdministration module (RSAT-ADCS-Tools) on the machine
      running the script if using 'New-CertificateRequest' directly with CA submission.
      However, this script uses 'certreq.exe' for submission, which is generally available.
    - Ensure the user running the script has permissions to request certificates using the
      specified template on the target CA.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$CaServer,

    [Parameter(Mandatory=$true)]
    [string]$CaName,

    [Parameter(Mandatory=$true)]
    [string]$TemplateName,

    [int]$NumberOfRequests = 10,

    [string]$OutputDirectory = ".\CertRequests"
)

Write-Host "Starting certificate request generation and submission..." -ForegroundColor Green

# Initialize counters and error list
$successfulRequests = 0
$failedRequests = 0
$errorDetails = @()
$generatedRequests = @() # To store details of successfully generated requests for submission

# Ensure the output directory exists
if (-not (Test-Path $OutputDirectory -PathType Container)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create directory '$OutputDirectory': $_"
        return
    }
}

# Phase 1: Generate all .req files
for ($i = 1; $i -le $NumberOfRequests; $i++) {
    $guid = [guid]::NewGuid().ToString()
    $commonName = "LoadTestCert-$guid"
    $reqFileName = Join-Path $OutputDirectory "$commonName.req"
    $infFileName = Join-Path $OutputDirectory "$commonName.inf"

    Write-Host "($i/$NumberOfRequests) Generating request file for CN: $commonName..." -ForegroundColor Cyan

    try {
        # Create a new certificate request using certreq utility
        # This creates a Pkcs10 request file.
        $infContent = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "CN=$commonName"
HashAlgorithm = sha256       ; Request uses sha256 hash
KeyAlgorithm = RSA           ; Key pair generated using RSA algorithm
Exportable = TRUE
KeyLength = 2048
KeySpec = 1
KeyUsage = 0x80              ; 80 = Digital Signature, 20 = Key Encipherment (bitmask)
ProviderName = "Microsoft Software Key Storage Provider"
ProviderType = 1
RequestType = PKCS10
KeyUsageProperty = NCRYPT_ALLOW_SIGNING_FLAG ; Private key only used for signing, not decryption
UseExistingKeySet = FALSE    ; Do not use an existing key pair
SMIME = FALSE                ; No secure email function

[Strings]
 szOID_ENHANCED_KEY_USAGE = "2.5.29.37"
 szOID_CODE_SIGN = "1.3.6.1.5.5.7.3.3"
 szOID_BASIC_CONSTRAINTS = "2.5.29.19"

[Extensions]
 %szOID_ENHANCED_KEY_USAGE% = "{text}%szOID_CODE_SIGN%"
 %szOID_BASIC_CONSTRAINTS% = "{text}ca=0&path length=0"

[RequestAttributes]
CertificateTemplate = "$TemplateName"
"@
        $infContent | Out-File $infFileName -Encoding ASCII -Force

        $LASTEXITCODE = 0;
        $certreqCreateResult = (certreq -new "$infFileName" "$reqFileName" 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            $failedRequests++
            $errorDetails += @{
                CommonName = $commonName
                Stage = "File Creation"
                Message = "Failed to create request file: $($certreqCreateResult | Out-String)"
                Timestamp = Get-Date
            }
            Write-Error "Failed to create request file for '$commonName'. Error recorded."
        } else {
            Write-Host "Successfully generated request file: $reqFileName" -ForegroundColor Green
            # Store details for later submission
            $generatedRequests += @{ CommonName = $commonName; ReqPath = $reqFileName }
        }
        Remove-Item $infFileName -ErrorAction SilentlyContinue # Clean up .inf file
    }
    catch {
        $failedRequests++
        $errorDetails += @{
            CommonName = $commonName
            Stage = "Unexpected Error (File Creation)"
            Message = "An unexpected error occurred: $($_.Exception.Message)"
            Timestamp = Get-Date
        }
        Write-Error "An unexpected error occurred during request file creation for '$commonName'. Error recorded."
    }
    Write-Host "" # Blank line for readability
}

Write-Host "`n--- Phase 2: Submitting Certificate Requests to CA ---" -ForegroundColor Yellow

# Phase 2: Submit generated .req files to the CA

# Record the start time
$startTime = Get-Date

$submitCount = 0
foreach ($request in $generatedRequests) {
    $submitCount++
    $commonName = $request.CommonName
    $reqFileName = $request.ReqPath
    $certificateFile = Join-Path $OutputDirectory "$commonName.cer"

    Write-Host "($submitCount/ $($generatedRequests.Count)) Submitting request for CN: $commonName..." -ForegroundColor DarkCyan

    try {
        $LASTEXITCODE = 0;
        $certreqSubmitResult = (certreq -f -submit -config "$CaServer\$CaName" -attrib "CertificateTemplate:$TemplateName" "$reqFileName" "$certificateFile" -f 2>&1) -join "`n"

        # Check the exit code of certreq.exe for success/failure
        if ($LASTEXITCODE -eq 0) {
            $successfulRequests++
            # Parse the output to find the Request ID
            $requestIdLine = ($certreqSubmitResult | Select-String "RequestId:").ToString()
            if ($requestIdLine) {
                $requestId = ($requestIdLine -split ':' | Select-Object -Last 1).Trim()
                Write-Host "Successfully submitted request for '$commonName'. Request ID: $requestId" -ForegroundColor Green
            } else {
                Write-Host "Successfully submitted request for '$commonName', but could not parse Request ID from output." -ForegroundColor Green
                Write-Verbose "certreq submit output: $($certreqSubmitResult | Out-String)"
            }
        } else {
            $failedRequests++
            $errorDetails += @{
                CommonName = $commonName
                Stage = "Submission to CA"
                Message = "Failed to submit request: $($certreqSubmitResult | Out-String)"
                Timestamp = Get-Date
            }
            Write-Error "Failed to submit request for '$commonName'. Error recorded."
        }
    }
    catch {
        $failedRequests++
        $errorDetails += @{
            CommonName = $commonName
            Stage = "Unexpected Error (Submission)"
            Message = "An unexpected error occurred: $($_.Exception.Message)"
            Timestamp = Get-Date
        }
        Write-Error "An unexpected error occurred during submission for '$commonName'. Error recorded."
    }
    Write-Host "" # Blank line for readability
}

# Record the end time
$endTime = Get-Date
$totalTime = $endTime - $startTime

Write-Host "===================================================" -ForegroundColor Green
Write-Host "                 LOAD TEST SUMMARY                 " -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host "Total Requests Attempted (Generated + Failed Gen): $($NumberOfRequests)" -ForegroundColor White # This is the total count of how many requests the user asked for.
Write-Host "Successfully Submitted:   $successfulRequests" -ForegroundColor Green
Write-Host "Failed Requests (Generation or Submission): $failedRequests" -ForegroundColor Red
Write-Host "Total Time Taken:         $totalTime" -ForegroundColor White

if ($totalTime.TotalSeconds -gt 0) {
    $requestsPerSecond = [math]::Round($successfulRequests / $totalTime.TotalSeconds, 2)
    Write-Host "Rate (Req/Sec):           $requestsPerSecond" -ForegroundColor White
} else {
    Write-Host "Rate (Req/Sec):           N/A (Total time is zero)" -ForegroundColor White
}

Write-Host "Output Directory:         $OutputDirectory" -ForegroundColor White
Write-Host "CA Server:                $CaServer" -ForegroundColor White
Write-Host "Template Name:            $TemplateName" -ForegroundColor White
Write-Host "===================================================" -ForegroundColor Green

if ($errorDetails.Count -gt 0) {
    Write-Host "`n--- Error Details ---" -ForegroundColor Red
    $errorDetails | ForEach-Object {
        Write-Host "  Timestamp: $($_.Timestamp)" -ForegroundColor Red
        Write-Host "  Common Name: $($_.CommonName)" -ForegroundColor Red
        Write-Host "  Stage: $($_.Stage)" -ForegroundColor Red
        Write-Host "  Message: $($_.Message.Trim())`n" -ForegroundColor Red
    }
}

Write-Host "Script finished. Check the CA for submitted requests." -ForegroundColor Green
