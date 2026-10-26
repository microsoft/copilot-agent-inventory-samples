#Requires -Version 7.0
#Requires -Modules PnP.PowerShell
<#
.SYNOPSIS
    Syncs the tenant's custom Copilot agents from the Microsoft Graph Package
    Management API into the SharePoint "Agents" list.

.DESCRIPTION
    - Lists all Copilot-hosted packages from the Graph v1.0 Package Management API.
    - Excludes first-party and third-party agents (keeps only 'shared' and 'lob').
    - Classifies each agent (Agent Builder / Copilot Studio / LOB / Unknown).
    - Resolves the owner and the shared-with users/groups to SharePoint logins.
    - Upserts each agent into the list: it looks the agent up by its package id
      (the 'Agent Id' column) and updates the existing item if found, otherwise
      creates a new one. Blank/null fields are dropped so a sync never overwrites
      existing data with empty values.

    Authentication is app-only via an Entra ID app registration with a certificate,
    using PnP.PowerShell. The same app registration is used for both Microsoft Graph
    and SharePoint, so it must be granted (with admin consent) the following
    application permissions:

      Microsoft Graph:      CopilotPackages.Read.All, User.Read.All, Group.Read.All
      SharePoint (or Graph) Sites.FullControl.All  (required by PnP.PowerShell CSOM writes)

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
    Absolute URL of the SharePoint site that hosts the list
    (e.g. https://contoso.sharepoint.com/sites/Governance).

.PARAMETER ListName
    Display name of the target SharePoint list. Defaults to 'Agents'.

.PARAMETER MaxAgents
    Optional cap on the number of agents processed (useful for testing).

.PARAMETER ThrottleLimit
    How many agents to fetch from Microsoft Graph in parallel (1-20, default 5).
    Only the Graph detail/owner lookups run in parallel; SharePoint writes are
    always sequential. Set to 1 to process everything sequentially.

.PARAMETER ClearList
    Deletes every existing item in the list before syncing, for a clean import.

.EXAMPLE
    .\Sync-CopilotAgents.ps1 -TenantId <tenant> -ClientId <appId> `
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
    [string] $ListName = 'Copilot Agents',

    [ValidateRange(0, 2147483647)]
    [int] $MaxAgents = 0,

    [ValidateRange(1, 1000)]
    [int] $BatchSize = 25,

    [ValidateRange(5, 300)]
    [int] $RequestTimeoutSeconds = 45,

    [ValidateRange(1, 20)]
    [int] $MaxConsecutiveFailures = 3,

    [string] $CheckpointPath,
    [switch] $Resume,

    # Number of agents to fetch from Graph in parallel (SharePoint writes stay sequential).
    [ValidateRange(1, 20)]
    [int] $ThrottleLimit = 2,

    # Delete every existing item in the list before syncing (useful for fresh imports).
    [switch] $ClearList
)

$ErrorActionPreference = 'Stop'
# StrictMode is intentionally not enabled: Graph returns heterogeneous JSON and
# optional manifest fields are often absent; referencing a missing property must
# yield $null rather than throw.

$GraphBase = 'https://graph.microsoft.com/v1.0'
$script:RequestTimeoutSeconds = $RequestTimeoutSeconds
if ($Resume -and $ClearList) { throw '-Resume cannot be combined with -ClearList.' }
$checkpointScope = "$($TenantId.ToLowerInvariant())|$($SiteUrl.TrimEnd('/').ToLowerInvariant())|$($ListName.ToLowerInvariant())"
if (-not $CheckpointPath) {
    $scopeHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($checkpointScope))).ToLowerInvariant()
    $CheckpointPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "CopilotAgentInventorySync/$scopeHash.json"
}
$script:CheckpointPath = [IO.Path]::GetFullPath($CheckpointPath)
$script:CheckpointState = @{ Version = 1; Scope = $checkpointScope; Completed = @{} }
if ($Resume) {
    if (-not (Test-Path -LiteralPath $script:CheckpointPath)) { throw 'Resume checkpoint not found. Run once without -Resume first.' }
    $savedState = Get-Content -LiteralPath $script:CheckpointPath -Raw | ConvertFrom-Json -AsHashtable
    if ($savedState.Version -ne 1 -or $savedState.Scope -ne $checkpointScope -or $savedState.Completed -isnot [System.Collections.IDictionary]) {
        throw 'Checkpoint version or tenant/site/list scope does not match this run.'
    }
    $script:CheckpointState = $savedState
}

function Save-SyncCheckpoint {
    if ($WhatIfPreference) { return }
    $directory = Split-Path -Parent $script:CheckpointPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = "$script:CheckpointPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $script:CheckpointState | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
        [IO.File]::Move($temporaryPath, $script:CheckpointPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

function Get-AgentType {
    <# Classifies a custom agent's build type from its elementTypes / type. #>
    param($Package)
    $elementTypes = @($Package.elementTypes)
    if ($elementTypes -contains 'CustomEngineCopilots') { return 'Copilot Studio' }
    if ($elementTypes -contains 'DeclarativeCopilots')  { return 'Agent Builder' }
    if ($Package.type -eq 'lob')                        { return 'LOB' }
    return 'Unknown'
}

function Get-AgentDistribution {
    <# Distinguishes a user-shared package (type 'shared') from an org-deployed one (type 'lob').
       The same agent can appear as both once it is submitted and approved for the org store,
       so this is what tells the two otherwise-identical list rows apart. #>
    param($Package)
    switch ($Package.type) {
        'shared' { 'Shared' }
        'lob'    { 'Org-deployed' }
        default  { $null }
    }
}

# ---------------------------------------------------------------------------
# REST helpers
# ---------------------------------------------------------------------------

function Invoke-WithRetry {
    <# Retries transient failures (429/5xx and connection drops) with exponential backoff. #>
    param([scriptblock] $Action, [int] $MaxAttempts = 4)
    for ($attempt = 1; ; $attempt++) {
        try { return & $Action }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            $transient = $status -in 0, 408, 429, 500, 502, 503, 504 -or $null -eq $status
            $statusLabel = if ($null -eq $status -or $status -eq 0) { 'no HTTP response' } else { "HTTP $status" }
            if (-not $transient -or $attempt -ge $MaxAttempts) {
                Write-Warning "Request failed ($statusLabel, attempt $attempt/$MaxAttempts): $($_.Exception.Message)"
                throw
            }
            $delay = [math]::Min(30, [math]::Pow(2, $attempt))
            $retryAfter = $_.Exception.Response.Headers.RetryAfter
            if ($retryAfter.Delta) { $delay = [math]::Max($delay, [math]::Ceiling($retryAfter.Delta.TotalSeconds)) }
            elseif ($retryAfter.Date) { $delay = [math]::Max($delay, [math]::Ceiling(($retryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds)) }
            Write-Warning "Request failed ($statusLabel, attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Invoke-GraphRequest {
    param([string] $Uri, [string] $Method = 'Get')
    if ($null -eq $script:GraphSession) {
        $script:GraphSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    }
    Invoke-WithRetry {
        Invoke-RestMethod -Method $Method -Uri $Uri -Headers $script:GraphHeaders -WebSession $script:GraphSession -TimeoutSec $script:RequestTimeoutSeconds
    }
}

# ---------------------------------------------------------------------------
# Directory resolution (cached) -> SharePoint login string
# ---------------------------------------------------------------------------

$script:PrincipalCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

function Resolve-Principal {
    <# Resolves a directory object id to a login usable by a SharePoint person/group field. #>
    param([string] $Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    if ($script:PrincipalCache.ContainsKey($Id)) {
        if ($script:PrincipalCache[$Id] -eq '') { return $null }
        return $script:PrincipalCache[$Id]
    }

    $login = $null
    try {
        # Single lookup resolves any directory object type (user, group, service principal).
        $o = Invoke-GraphRequest "$GraphBase/directoryObjects/$Id"
        if ($o.'@odata.type' -eq '#microsoft.graph.group') {
            # Claim format understood by SharePoint EnsureUser for Entra security groups.
            $login = "c:0o.c|federateddirectoryclaimprovider|$Id"
        }
        elseif ($o.userPrincipalName) {
            $login = $o.userPrincipalName
        }
        if ($login) { $script:PrincipalCache[$Id] = $login }  # cache successful resolutions only
    }
    catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status -ne 404) { throw }
        $script:PrincipalCache[$Id] = ''
        Write-Warning "Could not resolve principal '$Id': $($_.Exception.Message)"
    }
    return $login
}

# ---------------------------------------------------------------------------
# Manifest parsing
# ---------------------------------------------------------------------------

function Get-AgentManifest {
    <# Extracts the declarative agent definition (parsed JSON) from a package detail response. #>
    param($Detail)
    foreach ($ed in @($Detail.elementDetails)) {
        foreach ($el in @($ed.elements)) {
            if ($el.definition) {
                try { return ($el.definition | ConvertFrom-Json) } catch { }
            }
        }
    }
    return $null
}

function Get-Capability {
    param($Manifest, [string] $Name)
    @($Manifest.capabilities) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Join-Values {
    <# Joins an array into a unique, semicolon-delimited string for a multi-line column. #>
    param($Values)
    (@($Values) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Select-Object -Unique) -join '; '
}

function Build-AgentValues {
    <# Fetches a package's detail and builds the cleaned SharePoint field map (Graph only, no PnP). #>
    param($Package)

    $id = "$($Package.id)"
    $detail = Invoke-GraphRequest "$GraphBase/copilot/admin/catalog/packages/$id"
    $manifest = Get-AgentManifest -Detail $detail

    $capabilityNames = @($manifest.capabilities).name
    $graphConnectors = @(Get-Capability $manifest 'GraphConnectors').connections.connection_id
    $odsp            = @(Get-Capability $manifest 'OneDriveAndSharePoint').items_by_url.url
    $websites        = @(Get-Capability $manifest 'WebSearch').sites.url
    $prompts         = @($manifest.conversation_starters) | ForEach-Object { if ($_.title) { $_.title } else { $_.text } }

    $discourage = $false
    $special = $manifest.behavior_overrides.special_instructions
    if ($special -and $null -ne $special.discourage_model_knowledge) {
        $discourage = [bool]$special.discourage_model_knowledge
    }

    # Owner (single person). Prefer the detail's ownerId; fall back to the list summary.
    $ownerId = if ($detail.ownerId) { $detail.ownerId } else { $Package.ownerId }
    $ownerLogin = Resolve-Principal -Id $ownerId

    # Shared With (users/groups the agent is shared with, resolved to SharePoint logins).
    $sharedWith = @()
    foreach ($entry in @($detail.sharedWithUsersAndGroups)) {
        $principalId = if ($entry.resourceId) { $entry.resourceId } else { $entry }
        $login = Resolve-Principal -Id $principalId
        if ($login) { $sharedWith += $login }
    }

    $values = @{
        'Title'                      = "$($Package.displayName)"
        'Agent Id'                   = $id
        'Short Description'          = $Package.shortDescription
        'Long Description'           = $(if ($detail.longDescription) { $detail.longDescription } else { $Package.longDescription })
        'Blocked'                    = [bool]$Package.isBlocked
        'Agent Type'                 = Get-AgentType -Package $Package
        'Distribution'               = Get-AgentDistribution -Package $Package
        'Instructions'               = $manifest.instructions
        'Capabilities'               = Join-Values $capabilityNames
        'Graph Connector Ids'        = Join-Values $graphConnectors
        'Websites'                   = Join-Values $websites
        'ODSP Sites'                 = Join-Values $odsp
        'Suggested Prompts'          = Join-Values $prompts
        'Discourage Model Knowledge' = $discourage
        'Available To'               = $Package.availableTo
        'Deployed To'                = $Package.deployedTo
    }
    if ($Package.lastModifiedDateTime) { $values['Last Modified'] = [datetime]$Package.lastModifiedDateTime }
    if ($ownerLogin) { $values['Owner'] = $ownerLogin }
    if ($sharedWith.Count -gt 0) { $values['Shared With'] = $sharedWith }

    # Drop null/blank string values so we never overwrite existing data with empties.
    $clean = @{}
    foreach ($kvp in $values.GetEnumerator()) {
        if ($null -eq $kvp.Value) { continue }
        if (($kvp.Value -is [string]) -and $kvp.Value -eq '') { continue }
        $clean[$kvp.Key] = $kvp.Value
    }
    return $clean
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

# Acquire a Graph token from the same app-only connection.
$graphToken = Get-PnPAccessToken -ResourceTypeName Graph
if ($graphToken -is [securestring]) { $graphToken = [System.Net.NetworkCredential]::new('', $graphToken).Password }
$script:GraphHeaders = @{
    Authorization = "Bearer $graphToken"
    Accept        = 'application/json'
}

# ---------------------------------------------------------------------------
# Resolve list field internal names (display name -> internal name)
# ---------------------------------------------------------------------------

Write-Host "Reading list schema for '$ListName'..." -ForegroundColor Cyan

$fieldMap = @{}
foreach ($f in Get-PnPField -List $ListName) {
    # Prefer deletable (custom) fields when a display name collides with a built-in (e.g. 'Id' vs 'ID').
    if (-not $fieldMap.ContainsKey($f.Title) -or $f.CanBeDeleted) {
        $fieldMap[$f.Title] = $f.InternalName
    }
}

function Convert-ToInternalNames {
    param([hashtable] $Values)
    $out = @{}
    foreach ($key in $Values.Keys) {
        if ($fieldMap.ContainsKey($key)) {
            $out[$fieldMap[$key]] = $Values[$key]
        }
        else {
            Write-Warning "Column '$key' not found in list '$ListName'; skipping."
        }
    }
    return $out
}

$idInternal = if ($fieldMap.ContainsKey('Agent Id')) { $fieldMap['Agent Id'] } else { 'Agent_x0020_Id' }

# ---------------------------------------------------------------------------
# Optional: clear the list
# ---------------------------------------------------------------------------

if ($ClearList) {
    Write-Host "Clearing existing items from '$ListName'..." -ForegroundColor Yellow
    $cleared = 0
    foreach ($item in Get-PnPListItem -List $ListName -PageSize 500) {
        if ($PSCmdlet.ShouldProcess("item $($item.Id)", 'Delete list item')) {
            Remove-PnPListItem -List $ListName -Identity $item.Id -Force | Out-Null
            $cleared++
        }
    }
    Write-Host "  Deleted $cleared item(s)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Load existing items (for upsert by Agent Id)
# ---------------------------------------------------------------------------

Write-Host "Loading existing list items..." -ForegroundColor Cyan
$existingById = @{}
foreach ($item in Get-PnPListItem -List $ListName -Fields $idInternal -PageSize 500) {
    $key = "$($item.FieldValues[$idInternal])"
    if ($key) { $existingById[$key] = $item.Id }
}

# ---------------------------------------------------------------------------
# Fetch packages (Graph v1.0, paginated)
# ---------------------------------------------------------------------------

Write-Host "Retrieving Copilot packages from Graph (v1.0)..." -ForegroundColor Cyan
$packages = [System.Collections.Generic.List[object]]::new()
$filter   = [uri]::EscapeDataString("supportedHosts/any(h:h eq 'Copilot')")
$uri      = "$GraphBase/copilot/admin/catalog/packages?`$filter=$filter&`$top=100"
$pageNumber = 0
do {
    $pageNumber++
    Write-Host "  Fetching package page $pageNumber..." -ForegroundColor Cyan
    $pageTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-GraphRequest $uri
    foreach ($p in $resp.value) { $packages.Add($p) }
    Write-Host ("  Page {0}: {1} package(s) in {2:N1}s; {3} total." -f $pageNumber, @($resp.value).Count, $pageTimer.Elapsed.TotalSeconds, $packages.Count)
    $uri = $resp.'@odata.nextLink'
} while ($uri)

# Exclude 1P/3P - keep only custom agents (shared = shared via link, lob = admin deployed).
$customAgents = $packages | Where-Object { $_.type -in @('shared', 'lob') }
Write-Host ("Found {0} package(s); {1} custom agent(s) after excluding 1P/3P." -f $packages.Count, @($customAgents).Count) -ForegroundColor Green

$customAgents = @($customAgents | Sort-Object id -Unique | Where-Object {
    $packageId = [string]$_.id
    $stamp = "modified:$($_.lastModifiedDateTime)"
    -not ($Resume -and $existingById.ContainsKey($packageId) -and
        $script:CheckpointState.Completed.Contains($packageId) -and
        $script:CheckpointState.Completed[$packageId] -eq $stamp)
})
Write-Host ("Pending after resume checks: {0}. Checkpoint: {1}" -f $customAgents.Count, $script:CheckpointPath) -ForegroundColor Cyan
if ($MaxAgents -gt 0) { $customAgents = @($customAgents | Select-Object -First $MaxAgents) }
Save-SyncCheckpoint

# ---------------------------------------------------------------------------
# Phase 1 - fetch agent details and build records (parallel, Graph only)
# ---------------------------------------------------------------------------

Write-Host ("Fetching agent details (up to {0} in parallel)..." -f $ThrottleLimit) -ForegroundColor Cyan

# Capture helper function bodies and shared state so they can be rehydrated inside each
# parallel runspace - functions and $script:-scoped variables do not cross the boundary.
$graphBase          = $GraphBase
$graphHeaders       = $script:GraphHeaders
$principalCache     = $script:PrincipalCache
$fnInvokeWithRetry  = ${function:Invoke-WithRetry}.ToString()
$fnInvokeGraph      = ${function:Invoke-GraphRequest}.ToString()
$fnResolvePrincipal = ${function:Resolve-Principal}.ToString()
$fnGetAgentType     = ${function:Get-AgentType}.ToString()
$fnGetDistribution  = ${function:Get-AgentDistribution}.ToString()
$fnGetManifest      = ${function:Get-AgentManifest}.ToString()
$fnGetCapability    = ${function:Get-Capability}.ToString()
$fnJoinValues       = ${function:Join-Values}.ToString()
$fnBuildValues      = ${function:Build-AgentValues}.ToString()
$requestTimeout     = $RequestTimeoutSeconds
$created = 0; $updated = 0; $failed = 0
$consecutiveFailures = 0

function Get-AgentRecord {
    param($Package)
    try {
        $values = Build-AgentValues -Package $Package
        [pscustomobject]@{ Package = $Package; Values = $values; Error = $null; Transient = $false }
    } catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        [pscustomobject]@{
            Package = $Package; Values = $null; Error = $_.Exception.Message
            Transient = ($null -eq $status -or $status -in 0, 408, 429, 500, 502, 503, 504)
        }
    }
}
$fnGetRecord = ${function:Get-AgentRecord}.ToString()

for ($offset = 0; $offset -lt $customAgents.Count; $offset += $BatchSize) {
    $batch = @($customAgents | Select-Object -Skip $offset -First $BatchSize)
    $stopAfterBatch = $false
    Write-Host ("Batch {0}/{1}: fetching {2} agent(s)..." -f (1 + [int]($offset / $BatchSize)), [math]::Ceiling($customAgents.Count / $BatchSize), $batch.Count) -ForegroundColor Cyan
    $graphToken = Get-PnPAccessToken -ResourceTypeName Graph
    if ($graphToken -is [securestring]) { $graphToken = [System.Net.NetworkCredential]::new('', $graphToken).Password }
    $script:GraphHeaders.Authorization = "Bearer $graphToken"
    $graphHeaders = $script:GraphHeaders
    $fetchTimer = [Diagnostics.Stopwatch]::StartNew()

    if ($ThrottleLimit -eq 1) {
        $recordList = [System.Collections.Generic.List[object]]::new()
        $fetchFailures = 0
        foreach ($package in $batch) {
            Write-Host "  Fetching: $($package.displayName)"
            $record = Get-AgentRecord -Package $package
            $recordList.Add($record)
            if ($record.Transient) { $fetchFailures++ } else { $fetchFailures = 0 }
            if ($fetchFailures -ge $MaxConsecutiveFailures) { $stopAfterBatch = $true; break }
        }
        $records = @($recordList.ToArray())
    } else {
        $records = @($batch | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            ${function:Invoke-WithRetry}    = $using:fnInvokeWithRetry
            ${function:Invoke-GraphRequest} = $using:fnInvokeGraph
            ${function:Resolve-Principal}   = $using:fnResolvePrincipal
            ${function:Get-AgentType}       = $using:fnGetAgentType
            ${function:Get-AgentDistribution} = $using:fnGetDistribution
            ${function:Get-AgentManifest}   = $using:fnGetManifest
            ${function:Get-Capability}      = $using:fnGetCapability
            ${function:Join-Values}         = $using:fnJoinValues
            ${function:Build-AgentValues}   = $using:fnBuildValues
            ${function:Get-AgentRecord}     = $using:fnGetRecord
            $script:GraphBase      = $using:graphBase
            $script:GraphHeaders   = $using:graphHeaders
            $script:PrincipalCache = $using:principalCache
            $script:RequestTimeoutSeconds = $using:requestTimeout

            Get-AgentRecord -Package $_
        })
    }
    $fetchTimer.Stop()
    $writeTimer = [Diagnostics.Stopwatch]::StartNew()

    foreach ($rec in $records) {
        $pkg = $rec.Package
        $id = "$($pkg.id)"
        $displayName = "$($pkg.displayName)"

        if ($rec.Error) {
            $failed++
            if ($rec.Transient) { $consecutiveFailures++ } else { $consecutiveFailures = 0 }
            if ($consecutiveFailures -ge $MaxConsecutiveFailures) { $stopAfterBatch = $true }
            Write-Warning "Failed to fetch '$displayName' ($id): $($rec.Error)"
            continue
        }
        $wroteItem = $false
        try {
            $itemValues = Convert-ToInternalNames -Values $rec.Values

            if ($existingById.ContainsKey($id)) {
                if ($PSCmdlet.ShouldProcess("$displayName ($id)", 'Update list item')) {
                    Set-PnPListItem -List $ListName -Identity $existingById[$id] -Values $itemValues -ErrorAction Stop | Out-Null
                    $updated++
                    $wroteItem = $true
                    Write-Host "  Updated: $displayName" -ForegroundColor DarkGray
                }
            }
            else {
                if ($PSCmdlet.ShouldProcess("$displayName ($id)", 'Create list item')) {
                    $newItem = Add-PnPListItem -List $ListName -Values $itemValues -ErrorAction Stop
                    $existingById[$id] = $newItem.Id
                    $created++
                    $wroteItem = $true
                    Write-Host "  Created: $displayName" -ForegroundColor DarkGray
                }
            }
            $consecutiveFailures = 0
        }
        catch {
            $failed++
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            if ($null -eq $status -or $status -in 0, 408, 429, 500, 502, 503, 504) { $consecutiveFailures++ } else { $consecutiveFailures = 0 }
            if ($consecutiveFailures -ge $MaxConsecutiveFailures) { $stopAfterBatch = $true }
            Write-Warning "Failed to sync '$displayName' ($id): $($_.Exception.Message)"
        }
        if ($wroteItem) {
            $script:CheckpointState.Completed[$id] = "modified:$($pkg.lastModifiedDateTime)"
            Save-SyncCheckpoint
        }
    }
    $writeTimer.Stop()
    Write-Host ("Batch saved. Created: {0}, Updated: {1}, Failed: {2}." -f $created, $updated, $failed) -ForegroundColor Cyan
    Write-Host ("  Graph: {0:N1}s; SharePoint/checkpoint: {1:N1}s." -f $fetchTimer.Elapsed.TotalSeconds, $writeTimer.Elapsed.TotalSeconds) -ForegroundColor Cyan
    if ($stopAfterBatch) {
        Disconnect-PnPOnline
        throw "Stopped after repeated connection failures. Successful writes are saved; rerun with -Resume -CheckpointPath '$script:CheckpointPath'."
    }
}

Write-Host ''
Write-Host ("Sync complete. Created: {0}, Updated: {1}, Failed: {2}." -f $created, $updated, $failed) -ForegroundColor Green

Disconnect-PnPOnline
if ($failed -gt 0) { throw "$failed agent(s) failed. Rerun with -Resume to retry unfinished agents." }
