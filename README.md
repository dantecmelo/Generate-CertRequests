# Generate-CertRequests
Generate synthetic load against an ADCS CA

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
