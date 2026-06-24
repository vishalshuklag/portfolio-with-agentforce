# Automates Phase 2: creates a fresh Einstein Agent User, patches metadata, deploys, assigns permsets, activates.
# Usage: .\scripts\deploy-phase2-agent.ps1 -TargetOrg myorg -OwnerName "Your Name"

param(
    [Parameter(Mandatory = $true)]
    [string] $TargetOrg,

    [Parameter(Mandatory = $true)]
    [string] $OwnerName
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$BotMetaPath = Join-Path $RepoRoot "force-app\main\default\bots\Personal_Portfolio_Agent\Personal_Portfolio_Agent.bot-meta.xml"
$AgentPath = Join-Path $RepoRoot "force-app\main\default\aiAuthoringBundles\Personal_Portfolio_Agent\Personal_Portfolio_Agent.agent"
$ManifestPath = Join-Path $RepoRoot "manifest\package-phase2-agent.xml"
$AgentApiName = "Personal_Portfolio_Agent"

function Invoke-Sf {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = & sf @Arguments --json 2>&1
    if ($LASTEXITCODE -ne 0 -and -not ($output | Out-String).TrimStart().StartsWith("{")) {
        throw "sf $($Arguments -join ' ') failed: $output"
    }

    $result = $output | ConvertFrom-Json
    if ($null -ne $result.status -and $result.status -ne 0) {
        $message = if ($result.message) { $result.message } else { $result | ConvertTo-Json -Depth 5 }
        throw "sf $($Arguments -join ' ') failed: $message"
    }

    return $result
}

function Get-SfQueryRecord {
    param(
        [string] $Query
    )

    $result = Invoke-Sf @("data", "query", "--query", $Query, "--target-org", $TargetOrg)
    if ($null -eq $result.result.records -or $result.result.records.Count -eq 0) {
        return $null
    }
    return $result.result.records[0]
}

function Set-MetadataAgentUser {
    param([string] $Username)

    $botMeta = Get-Content -Path $BotMetaPath -Raw
    $botMeta = $botMeta -replace '(?s)(<botUser>)[^<]*(</botUser>)', "`${1}$Username`${2}"
    Set-Content -Path $BotMetaPath -Value $botMeta -NoNewline

    $agent = Get-Content -Path $AgentPath -Raw
    $agent = $agent -replace '(?m)^(\s*default_agent_user:\s*")[^"]*(")', "`${1}$Username`${2}"
    Set-Content -Path $AgentPath -Value $agent -NoNewline

    Write-Host "Updated botUser and default_agent_user -> $Username"
}

function Set-MetadataOwnerName {
    param([string] $Name)

    $agent = Get-Content -Path $AgentPath -Raw
    $agent = $agent -replace '(?m)^(\s*owner_name:\s*mutable string = ")[^"]*(")', "`${1}$Name`${2}"
    Set-Content -Path $AgentPath -Value $agent -NoNewline
    Write-Host "Updated owner_name -> $Name"
}

function Ensure-PermsetAssigned {
    param(
        [string] $PermsetName,
        [string] $Username
    )

    $escaped = $Username.Replace("'", "\'")
    $existing = Get-SfQueryRecord "SELECT Id FROM PermissionSetAssignment WHERE Assignee.Username = '$escaped' AND PermissionSet.Name = '$PermsetName' LIMIT 1"
    if ($null -ne $existing) {
        Write-Host "Permission set already assigned: $PermsetName"
        return
    }

    & sf org assign permset --name $PermsetName --on-behalf-of $Username --target-org $TargetOrg
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to assign permission set $PermsetName to $Username"
    }
    Write-Host "Assigned permission set: $PermsetName"
}

Write-Host "Phase 2 - Personal Portfolio Agent ($TargetOrg)"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($OwnerName)) {
    throw "OwnerName is required - pass your portfolio display name, e.g. -OwnerName ""Jane Doe"""
}
if ($OwnerName -eq "Vishal") {
    throw "OwnerName must be your name, not the template default ""Vishal""."
}

# 1) Create a fresh Einstein Agent User
$orgId = (Invoke-Sf @("org", "display", "--target-org", $TargetOrg)).result.id
Write-Host "Org ID: $orgId"

$profile = Get-SfQueryRecord "SELECT Id FROM Profile WHERE Name = 'Einstein Agent User' LIMIT 1"
if ($null -eq $profile) {
    throw "Profile 'Einstein Agent User' not found in org."
}

$suffix = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$agentUser = "portfolio_agent_$suffix@$orgId.ext"
Write-Host "Creating Einstein Agent user: $agentUser"

Invoke-Sf @(
    "data", "create", "record",
    "--sobject", "User",
    "--values", "Username='$agentUser' LastName='Portfolio Agent' Email='noreply@example.com' Alias='ptfagent' ProfileId='$($profile.Id)' TimeZoneSidKey='America/Los_Angeles' LocaleSidKey='en_US' EmailEncodingKey='UTF-8' LanguageLocaleKey='en_US'",
    "--target-org", $TargetOrg
) | Out-Null

# 2) Patch local metadata (owner name + agent user - before deploy/activate)
Set-MetadataOwnerName -Name $OwnerName
Set-MetadataAgentUser -Username $agentUser

# 3) Permission sets (required before deploy — botUser must have agent access)
Write-Host ""
Ensure-PermsetAssigned -PermsetName "AgentforceServiceAgentUser" -Username $agentUser
Ensure-PermsetAssigned -PermsetName "Portfolio_Agent_Access" -Username $agentUser

# 4) Deploy Phase 2 manifest
Write-Host ""
Write-Host "Deploying manifest/package-phase2-agent.xml..."
& sf project deploy start --manifest $ManifestPath --target-org $TargetOrg
if ($LASTEXITCODE -ne 0) {
    throw "Phase 2 deploy failed."
}
Write-Host "Deploy succeeded."

# 5) Activate
Write-Host ""
Write-Host "Activating agent..."
& sf agent activate --api-name $AgentApiName --target-org $TargetOrg
if ($LASTEXITCODE -ne 0) {
    throw "Agent activation failed."
}

Write-Host ""
Write-Host "Phase 2 complete."
Write-Host "  Owner name:  $OwnerName"
Write-Host "  Agent user:  $agentUser"
Write-Host "  Agent:       $AgentApiName (activated)"
Write-Host ""
Write-Host "Next: create the site shell, then deploy Phase 3:"
Write-Host "  .\scripts\create-portfolio-site.ps1 -TargetOrg $TargetOrg"
