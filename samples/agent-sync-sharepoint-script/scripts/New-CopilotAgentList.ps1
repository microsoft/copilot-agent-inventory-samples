<#
.SYNOPSIS
    Provisions the SharePoint "Agents" list (and all of its columns) used by
    Sync-CopilotAgents.ps1.

.DESCRIPTION
    Creates a generic SharePoint list with the full column set that the sync script
    expects, configures the Agent Type choices, and applies the provided column
    formatting JSON to the Capabilities and Graph Connector Ids columns.

    Authentication is app-only via an Entra ID app registration with a certificate,
    using PnP.PowerShell. The app registration must be granted (with admin consent)
    the SharePoint (or Graph) Sites.FullControl.All application permission required by
    PnP.PowerShell to create lists and fields.

    The script is idempotent: the list and any column that already exists are skipped,
    so it is safe to re-run.

    Requires the PnP.PowerShell module:  Install-Module PnP.PowerShell -Scope CurrentUser

.PARAMETER TenantId
    Directory (tenant) ID of your Microsoft 365 tenant.

.PARAMETER ClientId
    Application (client) ID of the Entra ID app registration.

.PARAMETER CertificateThumbprint
    Thumbprint of a certificate installed in the current user's certificate store
    (Cert:\CurrentUser\My) whose public key is uploaded to the app registration.
    Use this OR -CertificatePath.

.PARAMETER CertificatePath
    Path to a PFX certificate file. Use this OR -CertificateThumbprint.

.PARAMETER CertificatePassword
    SecureString password for the PFX file supplied via -CertificatePath.

.PARAMETER SiteUrl
    Absolute URL of the SharePoint site that will host the list
    (e.g. https://contoso.sharepoint.com/sites/Governance).

.PARAMETER ListName
    Display name of the list to create. Defaults to 'Agents'.

.EXAMPLE
    .\New-CopilotAgentList.ps1 -TenantId <tenant> -ClientId <appId> `
        -CertificateThumbprint <thumbprint> `
        -SiteUrl https://contoso.sharepoint.com/sites/Governance -ListName Agents

.NOTES
    This is a sample and is not covered by a Microsoft support SLA.
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Thumbprint')]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $ClientId,

    [Parameter(Mandatory, ParameterSetName = 'Thumbprint')]
    [string] $CertificateThumbprint,

    [Parameter(Mandatory, ParameterSetName = 'CertFile')]
    [string] $CertificatePath,
    [Parameter(ParameterSetName = 'CertFile')]
    [securestring] $CertificatePassword,

    [Parameter(Mandatory)] [string] $SiteUrl,
    [string] $ListName = 'Copilot Agents'
)

#Requires -Modules PnP.PowerShell

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Column definitions
#
# Each column's schema maps to a SharePoint field XML template below. The display
# names MUST match the names the sync script writes to (it resolves display name ->
# internal name at run time). 'Agent Id' is used instead of 'Id' because a custom
# 'Id' column collides with the built-in read-only ID field.
# ---------------------------------------------------------------------------

$Columns = @(
    @{ Display = 'Agent Id';                   Internal = 'AgentId';                  Type = 'Text' }
    @{ Display = 'Short Description';           Internal = 'ShortDescription';         Type = 'Note' }
    @{ Display = 'Long Description';            Internal = 'LongDescription';          Type = 'Note' }
    @{ Display = 'Instructions';               Internal = 'Instructions';             Type = 'Note' }
    @{ Display = 'Blocked';                    Internal = 'Blocked';                  Type = 'Boolean' }
    @{ Display = 'Last Modified';              Internal = 'AgentLastModified';        Type = 'DateTime' }
    @{ Display = 'Agent Type';                 Internal = 'AgentType';                Type = 'Choice'
        Choices = @('Agent Builder', 'Copilot Studio', 'LOB', 'Unknown') }
    @{ Display = 'Capabilities';               Internal = 'Capabilities';             Type = 'Note'; Formatting = 'capabilities.json' }
    @{ Display = 'Graph Connector Ids';        Internal = 'GraphConnectorIds';        Type = 'Note'; Formatting = 'graph-connector-ids.json' }
    @{ Display = 'Websites';                   Internal = 'Websites';                 Type = 'Note' }
    @{ Display = 'ODSP Sites';                 Internal = 'ODSPSites';                Type = 'Note' }
    @{ Display = 'Suggested Prompts';          Internal = 'SuggestedPrompts';         Type = 'Note' }
    @{ Display = 'Owner';                      Internal = 'AgentOwner';               Type = 'User' }
    @{ Display = 'Discourage Model Knowledge'; Internal = 'DiscourageModelKnowledge'; Type = 'Boolean' }
    @{ Display = 'Available To';               Internal = 'AvailableTo';              Type = 'Text' }
    @{ Display = 'Deployed To';                Internal = 'DeployedTo';               Type = 'Text' }
    @{ Display = 'Shared With';                Internal = 'SharedWith';               Type = 'UserMulti' }
)

$FormattingRoot = Join-Path $PSScriptRoot '..\column-formatting'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function New-FieldXml {
    <# Builds a SharePoint field schema XML string for a column definition. #>
    param([hashtable] $Spec)

    $display = [System.Security.SecurityElement]::Escape($Spec.Display)
    $name = $Spec.Internal
    $common = "DisplayName=`"$display`" Name=`"$name`" StaticName=`"$name`""

    switch ($Spec.Type) {
        'Text'      { return "<Field Type=`"Text`" $common />" }
        'Note'      { return "<Field Type=`"Note`" $common RichText=`"FALSE`" NumLines=`"6`" />" }
        'Boolean'   { return "<Field Type=`"Boolean`" $common><Default>0</Default></Field>" }
        'DateTime'  { return "<Field Type=`"DateTime`" $common Format=`"DateTime`" />" }
        'User'      { return "<Field Type=`"User`" $common List=`"UserInfo`" ShowField=`"ImnName`" UserSelectionMode=`"PeopleOnly`" />" }
        'UserMulti' { return "<Field Type=`"UserMulti`" $common List=`"UserInfo`" ShowField=`"ImnName`" UserSelectionMode=`"PeopleAndGroups`" Mult=`"TRUE`" />" }
        'Choice'    {
            $choices = ($Spec.Choices | ForEach-Object { "<CHOICE>$([System.Security.SecurityElement]::Escape($_))</CHOICE>" }) -join ''
            return "<Field Type=`"Choice`" $common Format=`"Dropdown`"><CHOICES>$choices</CHOICES></Field>"
        }
        default { throw "Unknown column type '$($Spec.Type)'." }
    }
}

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------

Write-Host "Connecting to SharePoint ($SiteUrl) app-only..." -ForegroundColor Cyan

$connectArgs = @{
    Url      = $SiteUrl
    ClientId = $ClientId
    Tenant   = $TenantId
}
if ($PSCmdlet.ParameterSetName -eq 'Thumbprint') {
    $connectArgs.Thumbprint = $CertificateThumbprint
}
else {
    $connectArgs.CertificatePath = $CertificatePath
    if ($CertificatePassword) { $connectArgs.CertificatePassword = $CertificatePassword }
}
Connect-PnPOnline @connectArgs

# ---------------------------------------------------------------------------
# Create the list
# ---------------------------------------------------------------------------

# Derive a URL-safe name (no spaces) so the list URL contains no encoded
# characters, while the list keeps a friendly display name with a space.
$listUrl = $ListName -replace '\s', ''

$list = Get-PnPList -Identity $ListName -ErrorAction SilentlyContinue
if (-not $list) { $list = Get-PnPList -Identity "Lists/$listUrl" -ErrorAction SilentlyContinue }
if ($list) {
    Write-Host "List '$ListName' already exists - will add any missing columns." -ForegroundColor Yellow
}
elseif ($PSCmdlet.ShouldProcess($ListName, 'Create SharePoint list')) {
    Write-Host "Creating list '$ListName' (URL: Lists/$listUrl)..." -ForegroundColor Cyan
    $list = New-PnPList -Title $ListName -Url "Lists/$listUrl" -Template GenericList -EnableVersioning
    Write-Host "  Created list '$ListName' at Lists/$listUrl." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Add columns
# ---------------------------------------------------------------------------

$existingFields = @{}
foreach ($f in Get-PnPField -List $ListName) {
    $existingFields[$f.Title] = $true
    $existingFields[$f.InternalName] = $true
}

foreach ($col in $Columns) {
    if ($existingFields.ContainsKey($col.Display) -or $existingFields.ContainsKey($col.Internal)) {
        Write-Host "  Skipped (exists): $($col.Display)" -ForegroundColor DarkGray
        continue
    }
    if ($PSCmdlet.ShouldProcess($col.Display, "Add column")) {
        Add-PnPFieldFromXml -List $ListName -FieldXml (New-FieldXml $col) | Out-Null
        Write-Host "  Added: $($col.Display)" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Apply column formatting
# ---------------------------------------------------------------------------

foreach ($col in $Columns) {
    if (-not $col.ContainsKey('Formatting')) { continue }

    $path = Join-Path $FormattingRoot $col.Formatting
    if (-not (Test-Path $path)) {
        Write-Warning "Formatting file not found for '$($col.Display)': $path"
        continue
    }
    if ($PSCmdlet.ShouldProcess($col.Display, 'Apply column formatting')) {
        $json = Get-Content -Path $path -Raw
        try { $null = $json | ConvertFrom-Json -ErrorAction Stop }
        catch { Write-Warning "Skipping formatting for '$($col.Display)' - invalid JSON in $path`: $($_.Exception.Message)"; continue }
        # Set CustomFormatter directly via CSOM: Set-PnPField -Values coerces the
        # value to a PSObject and SharePoint then rejects it ("cannot convert PSObject to String").
        $field = Get-PnPField -List $ListName -Identity $col.Internal
        $field.CustomFormatter = [string]$json
        $field.UpdateAndPushChanges($true)
        Invoke-PnPQuery
        Write-Host "  Formatted: $($col.Display)" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Add the columns to the default view
#
# Fields created via Add-PnPFieldFromXml are added to the list but not to any view,
# so the default view is set here to show Title plus every column in schema order.
# ---------------------------------------------------------------------------

$defaultView = Get-PnPView -List $ListName | Where-Object { $_.DefaultView } | Select-Object -First 1
if ($defaultView -and $PSCmdlet.ShouldProcess($defaultView.Title, 'Update default view columns')) {
    # Internal field order: Title, Agent Id, then the rest (mirrors the 'Agents' list).
    $viewFields = @(
        'LinkTitle', 'AgentId', 'ShortDescription', 'Blocked', 'AgentLastModified', 'AgentType',
        'Instructions', 'LongDescription', 'Capabilities', 'GraphConnectorIds', 'Websites',
        'ODSPSites', 'AgentOwner', 'SuggestedPrompts', 'DiscourageModelKnowledge',
        'AvailableTo', 'DeployedTo', 'SharedWith'
    )
    Set-PnPView -List $ListName -Identity $defaultView.Title -Fields $viewFields | Out-Null
    Write-Host "  Default view ('$($defaultView.Title)') updated with $($viewFields.Count) columns." -ForegroundColor Green
}

Write-Host ''
Write-Host "Done. List '$ListName' is ready. Run Sync-CopilotAgents.ps1 to populate it." -ForegroundColor Cyan

Disconnect-PnPOnline
