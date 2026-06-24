# Creates the LWR Experience Cloud site shell required before Phase 3 deploy.
# Usage: .\scripts\create-portfolio-site.ps1 -TargetOrg myorg [-SiteName My_Portfolio] [-UrlPathPrefix myportfolio]

param(
    [Parameter(Mandatory = $true)]
    [string] $TargetOrg,

    [string] $SiteName = "My_Portfolio",
    [string] $UrlPathPrefix = "myportfolio"
)

$ErrorActionPreference = "Stop"

Write-Host "Creating LWR site '$SiteName' (Digital Experience bundle will be '${SiteName}1')..."

$result = sf community create `
    --name $SiteName `
    --template-name "Build Your Own (LWR)" `
    --url-path-prefix $UrlPathPrefix `
    --description "Personal Portfolio site" `
    templateParams.AuthenticationType=AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED `
    --target-org $TargetOrg `
    --json | ConvertFrom-Json

if ($result.status -ne 0) {
    Write-Error "Site creation failed: $($result | ConvertTo-Json -Depth 5)"
}

$jobId = $result.result.jobId
Write-Host "Job ID: $jobId — waiting for site shell..."

for ($i = 0; $i -lt 60; $i++) {
    $job = sf data query `
        --query "SELECT Id, Status, Error FROM BackgroundOperation WHERE Id = '$jobId'" `
        --target-org $TargetOrg `
        --json | ConvertFrom-Json

    $status = $job.result.records[0].Status
    Write-Host "  Status: $status"

    if ($status -eq "Complete") {
        Write-Host ""
        Write-Host "Site shell ready. Network label: $SiteName"
        Write-Host "Digital Experience bundle API name: ${SiteName}1"
        Write-Host ""
        Write-Host "Next: sf project deploy start --manifest manifest/package-phase3-site.xml --target-org $TargetOrg"
        exit 0
    }

    if ($status -eq "Error" -or $status -eq "Failed") {
        Write-Error "Site creation failed: $($job.result.records[0].Error)"
    }

    Start-Sleep -Seconds 10
}

Write-Error "Timed out waiting for site creation (job $jobId)."
