# Copilot Agent Inventory – SharePoint Sync (PowerShell)

> **This is a sample.**
> This solution demonstrates how the **Microsoft Graph Package Management API** can be used with **PowerShell** to provision a **SharePoint list** and sync your tenant's Copilot agent inventory to it — giving IT admins a familiar, filterable, and shareable view of all agents using **application (app-only) authentication**.
>
> It is intended as a **reference implementation and starting point**, not a production-ready solution.
>
> **⚠️ Disclaimer:** Parts of this sample were "vibe coded" — rapidly built with AI assistance. Review and test it thoroughly in a non-production environment before deploying to production.
>
> Prefer a no-code approach? See the [Agent Sync SharePoint (Flow)](../agent-sync-sharepoint/) sample, which performs the same sync with a Power Automate flow.

---

## Overview

This sample contains two PowerShell scripts, both using [PnP.PowerShell](https://pnp.github.io/powershell/) with **application (app-only) authentication**:

| Script | Description |
| --- | --- |
| [`scripts/New-CopilotAgentList.ps1`](scripts/New-CopilotAgentList.ps1) | Provisions the SharePoint **Agents** list — creates the list, adds every column with the correct type, configures the **Agent Type** choices, and applies the column formatting JSON. Idempotent, so it is safe to re-run. |
| [`scripts/Sync-CopilotAgents.ps1`](scripts/Sync-CopilotAgents.ps1) | Calls the Package Management API, retrieves detail for each agent, and **upserts** one list item per agent (matched on the `Agent Id` column). Supports pagination and can be run repeatedly without creating duplicates. |

The scripts sync **custom agents only** — those built in Agent Builder, Copilot Studio, or as custom declarative agents (`type` of `shared` or `lob`). First-party (Microsoft) and third-party (store/partner) agents are skipped. The `Agent Type` column is classified from the agent's `elementTypes` and `type` fields (`CustomEngineCopilots` → Copilot Studio, `DeclarativeCopilots` → Agent Builder, `lob` → LOB, otherwise Unknown).

The same agent can appear **twice** — once as a user-**shared** package and again as an **org-deployed** package — after it is submitted to and approved for the organization's store. These are distinct packages with different ids, so both are listed; the `Distribution` column tells them apart (`Shared` for `type` `shared`, `Org-deployed` for `type` `lob`).

---

## Prerequisites

- A Microsoft 365 tenant with [Microsoft 365 Copilot licences](https://learn.microsoft.com/microsoft-365-copilot/extensibility/prerequisites#prerequisites)
- Access to the Package Management API — requires an Agent 365 license.
- A **SharePoint site** where you have permission to create lists.
- [PnP.PowerShell](https://pnp.github.io/powershell/) — `Install-Module PnP.PowerShell -Scope CurrentUser`
- A **single Entra ID app registration** — used for *both* Microsoft Graph and SharePoint — with a **certificate** credential, granted admin consent for the following **application** permissions:

  | API | Permission | Used for |
  | --- | --- | --- |
  | Microsoft Graph | `CopilotPackages.Read.All` | List and read Copilot agents |
  | Microsoft Graph | `User.Read.All` | Resolve agent owners |
  | Microsoft Graph | `Group.Read.All` | Resolve shared groups |
  | SharePoint | `Sites.FullControl.All` | Create the list and write items (required by PnP.PowerShell) |

  Unlike the OAuth connection used by the [Flow sample](../agent-sync-sharepoint/), PnP.PowerShell app-only access **requires a certificate** — a client secret is not supported.

---

## Configure PnP PowerShell (app-only authentication)

PnP.PowerShell requires you to register your own Entra ID application ([mandatory since September 2024](https://pnp.github.io/powershell/articles/registerapplication.html)). For unattended scripts, register an **app-only** application that authenticates with a certificate.

> **One app registration does it all.** The scripts use a *single* app registration for both the Microsoft Graph (Package Management) reads and the SharePoint list writes — there is no separate "PnP PowerShell" app to create. The `Register-PnPEntraIDApp` command below registers that one app and its certificate; you then add the remaining Graph permissions from the [Prerequisites](#prerequisites) table to the same app. If you already have a PnP PowerShell app registration, you can reuse it — just make sure it has all four permissions above and a certificate credential.

### Register the app and certificate

The quickest way is the built-in `Register-PnPEntraIDApp` cmdlet, which creates the app registration, generates a self-signed certificate, uploads the public key, and writes the `.cer`/`.pfx` to `-OutPath`:

```powershell
$app = Register-PnPEntraIDApp `
    -ApplicationName 'Copilot Agent Inventory Sync' `
    -Tenant contoso.onmicrosoft.com `
    -OutPath C:\certs `
    -DeviceLogin `
    -SharePointApplicationPermissions 'Sites.FullControl.All' `
    -GraphApplicationPermissions 'User.Read.All', 'Group.Read.All'
$app   # outputs the ClientId and the base64-encoded private key
```

Follow the device-login prompt to grant admin consent, and note the **ClientId** from the output.

> **`CopilotPackages.Read.All` must be added manually.** The `-GraphApplicationPermissions` parameter has a fixed allow-list that does not include `CopilotPackages.Read.All`. After registering, add it in the [Entra portal](https://entra.microsoft.com/) (App registrations → your app → API permissions → Add a permission → Microsoft Graph → Application permissions) and click **Grant admin consent**, or use the Azure CLI:
>
> ```powershell
> az ad app permission add --id <clientId> --api 00000003-0000-0000-c000-000000000000 --api-permissions 72f0655d-6228-4ddc-8e1b-164973b9213b=Role
> az ad app permission admin-consent --id <clientId>
> ```

### How the scripts supply the certificate

Both scripts connect for you via `Connect-PnPOnline`; you just choose how the certificate is provided:

- **Windows certificate store** — import the `.pfx` into `Cert:\CurrentUser\My` and pass `-CertificateThumbprint <thumbprint>`.
- **PFX file** — pass `-CertificatePath <path.pfx>` (plus `-CertificatePassword` if the file is protected). Best for cloud/unattended hosts (see [Scheduling the sync](#scheduling-the-sync)).

### Reference

- [Register an Entra ID application for PnP PowerShell (App Only access)](https://pnp.github.io/powershell/articles/registerapplication.html#setting-up-access-to-your-own-entra-id-app-for-app-only-access)
- [PnP PowerShell non-interactive (certificate) authentication](https://pnp.github.io/powershell/articles/authentication.html#non-interactive-authentication)
- [Determining which PnP PowerShell permissions you need](https://pnp.github.io/powershell/articles/determinepermissions.html)

---

## Setup and deployment

### 1. Create the SharePoint list

Run the provisioning script to create the list and all of its columns:

```powershell
./scripts/New-CopilotAgentList.ps1 `
    -TenantId    <tenant-id> `
    -ClientId    <app-client-id> `
    -CertificateThumbprint <thumbprint> `
    -SiteUrl     https://contoso.sharepoint.com/sites/Governance `
    -ListName    "Copilot Agents"
```

This creates a **Copilot Agents** list (at the unencoded URL `Lists/CopilotAgents`) with the following schema and applies the colour-coded column formatting from [`column-formatting/`](column-formatting/) to the **Capabilities** and **Graph Connector Ids** columns:

| Column name | Type |
| --- | --- |
| Agent Id | Single line of text |
| Short Description | Multiple lines of text |
| Long Description | Multiple lines of text |
| Instructions | Multiple lines of text |
| Blocked | Yes/No |
| Last Modified | Date and Time |
| Agent Type | Choice (`Agent Builder`, `Copilot Studio`, `LOB`, `Unknown`) |
| Distribution | Choice (`Shared`, `Org-deployed`) |
| Capabilities | Multiple lines of text |
| Graph Connector Ids | Multiple lines of text |
| Websites | Multiple lines of text |
| ODSP Sites | Multiple lines of text |
| Suggested Prompts | Multiple lines of text |
| Owner | Person or Group |
| Discourage Model Knowledge | Yes/No |
| Available To | Single line of text |
| Deployed To | Single line of text |
| Shared With | Person or Group (groups allowed) |

> Use `-CertificatePath` / `-CertificatePassword` instead of `-CertificateThumbprint` to authenticate with a PFX file. Pass `-WhatIf` to preview the list and columns that would be created without making changes.

### 2. Sync the agent inventory

Run the sync script to populate (or refresh) the list:

```powershell
./scripts/Sync-CopilotAgents.ps1 `
    -TenantId    <tenant-id> `
    -ClientId    <app-client-id> `
    -CertificateThumbprint <thumbprint> `
    -SiteUrl     https://contoso.sharepoint.com/sites/Governance `
    -ListName    "Copilot Agents"
```

Use `-CertificatePath` / `-CertificatePassword` instead of `-CertificateThumbprint` to authenticate with a PFX file. Pass `-MaxAgents <n>` to process at most *n* pending agents (useful for testing), `-ClearList` to delete all existing items before syncing, or `-WhatIf` to preview the changes without writing anything.

> **Allow for long runtimes.** Large inventories can take many hours to sync. In one test, the main sync pass processing approximately **11,000 agent packages took 10 hours 32 minutes**, including network retries, with batches of 25 and two parallel Graph workers. This is an observation, not a guaranteed duration: agent count, owner/group lookups, network latency, service throttling, and sequential SharePoint writes all affect runtime.
>
> Plan for an overnight run, test a small batch with `-MaxAgents` first, and ensure your scheduled host's execution limits accommodate the workload. Keep the checkpoint in persistent storage so an interrupted run can continue with [`-Resume`](#resume-an-interrupted-sync).

By default the script processes **25 agents per batch**, fetching up to **2 agents from Graph in parallel**. Tune these with `-BatchSize <1-1000>` and `-ThrottleLimit <1-20>` (set `1` for fully sequential). Each batch is written to SharePoint before the next batch is fetched. SharePoint writes are always sequential.

Graph requests reuse an HTTP session per worker, including retries, reducing repeated connection setup. On PowerShell 7.4 and later this retains the underlying HTTP connection pool. The initial SharePoint read requests only the `Agent Id` field instead of downloading instructions and other large inventory fields. Each completed batch reports separate Graph-fetch and SharePoint/checkpoint times.

For a large inventory, start with `-ThrottleLimit 2`; increasing concurrency aggressively can increase service throttling. HTTP 429 indicates throttling, while a timeout or connection failure without an HTTP response is not evidence of throttling by itself. The script honors `Retry-After` when supplied. Reuse connections and inspect the batch timings before increasing the worker count.

### Resume an interrupted sync

Each successful SharePoint write is saved to a local JSON checkpoint. The default location is a tenant/site/list-specific file under the current user's local application data folder (`CopilotAgentInventorySync`); its path is printed at startup. Use `-CheckpointPath` to select a persistent location outside the repository. Checkpoints contain agent IDs and modification timestamps, not credentials. Do not share one checkpoint between concurrent runs.

```powershell
$sync = @{
  TenantId = '<tenant-id>'
  ClientId = '<app-client-id>'
  CertificateThumbprint = '<thumbprint>'
  SiteUrl = 'https://contoso.sharepoint.com/sites/Governance'
  ListName = 'Copilot Agents'
  CheckpointPath = "$env:LOCALAPPDATA/CopilotAgentInventorySync/inventory.json"
  BatchSize = 25
  ThrottleLimit = 1
}
./scripts/Sync-CopilotAgents.ps1 @sync -MaxAgents 25
./scripts/Sync-CopilotAgents.ps1 @sync -Resume -MaxAgents 25
```

`-Resume` skips checkpointed agents that still exist in the list and have the same package modification timestamp. It applies `-MaxAgents` **after** that check, so repeated limited runs advance through pending agents. Failed agents remain pending. Omit `-Resume` for a fresh full refresh and a new checkpoint. A missing checkpoint or mismatched tenant/site/list is rejected; `-Resume` cannot be combined with `-ClearList`. `-WhatIf` does not change the list or checkpoint.

Graph requests time out after 45 seconds by default (`-RequestTimeoutSeconds <5-300>`). Transient failures receive up to four attempts with exponential backoff, honoring `Retry-After`. After three consecutive transient agent failures (`-MaxConsecutiveFailures`), the script saves successful records from the current batch and stops with an error. With parallel fetching, the current batch finishes before stopping. Any remaining failures also produce a failing exit status, allowing schedulers to detect incomplete runs.

Re-run the script at any time to refresh the inventory; items are matched on the `Agent Id` column and updated in place, so no duplicates are created. Blank or missing fields are skipped, so a re-sync never overwrites existing data with empty values.

---

## Scheduling the sync

`Sync-CopilotAgents.ps1` has no built-in scheduler, but it is designed to run unattended on a recurring basis: it uses app-only (certificate) authentication, upserts items so it is safe to re-run on any cadence, retries transient failures, and exits cleanly. To keep the list up to date, run it on a schedule from any of the following hosts.

> For cloud hosts where you cannot rely on a certificate in `Cert:\CurrentUser\My`, use `-CertificatePath` / `-CertificatePassword` with a PFX stored in a secret store (e.g. Azure Key Vault) instead of `-CertificateThumbprint`.

### Azure Automation (recommended)

A PowerShell runbook with a recurring schedule is the most common fit for governance workloads.

1. Create (or reuse) an **Azure Automation account**.
2. Add the **PnP.PowerShell** module from the modules gallery (ensure the account uses the PowerShell 7.x runtime).
3. Upload your app registration's certificate under **Shared Resources > Certificates**, or store the PFX in **Azure Key Vault** and retrieve it in the runbook.
4. Create a **PowerShell runbook** whose body calls the script (or paste the script's contents), passing the parameters. Store secrets as **automation variables** rather than hard-coding them:

   ```powershell
   $cert = Get-AutomationCertificate -Name 'CopilotInventoryCert'
   # ... export to a temp PFX or pass the thumbprint if the cert is in the sandbox store ...
   ./Sync-CopilotAgents.ps1 `
       -TenantId   (Get-AutomationVariable -Name 'TenantId') `
       -ClientId   (Get-AutomationVariable -Name 'ClientId') `
       -CertificateThumbprint $cert.Thumbprint `
       -SiteUrl    (Get-AutomationVariable -Name 'SiteUrl') `
       -ListName   'Copilot Agents'
   ```

5. Attach a **schedule** (e.g. daily) to the runbook.

### Azure Functions (timer trigger)

A PowerShell function app with a timer trigger (CRON expression, e.g. `0 0 6 * * *` for 06:00 daily) gives a serverless option. Install PnP.PowerShell via `requirements.psd1`, and load the certificate from Key Vault using the function's managed identity.

### GitHub Actions (scheduled workflow)

Use a `schedule:` cron trigger on a hosted runner. Store the PFX (base64) and password as repository secrets, decode and import the certificate at the start of the job, then run the script.

```yaml
on:
  schedule:
    - cron: '0 6 * * *'   # 06:00 UTC daily
jobs:
  sync:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - shell: pwsh
        run: Install-Module PnP.PowerShell -Scope CurrentUser -Force
      - shell: pwsh
        env:
          PFX_BASE64: ${{ secrets.CERT_PFX_BASE64 }}
          PFX_PASSWORD: ${{ secrets.CERT_PFX_PASSWORD }}
        run: |
          [IO.File]::WriteAllBytes("$env:RUNNER_TEMP/cert.pfx", [Convert]::FromBase64String($env:PFX_BASE64))
          $pwd = ConvertTo-SecureString $env:PFX_PASSWORD -AsPlainText -Force
          ./samples/agent-sync-sharepoint-script/scripts/Sync-CopilotAgents.ps1 `
              -TenantId ${{ secrets.TENANT_ID }} -ClientId ${{ secrets.CLIENT_ID }} `
              -CertificatePath "$env:RUNNER_TEMP/cert.pfx" -CertificatePassword $pwd `
              -SiteUrl ${{ secrets.SITE_URL }} -ListName 'Copilot Agents'
```

### Windows Task Scheduler

On a server or VM where the certificate is installed in `Cert:\CurrentUser\My`, create a scheduled task that runs:

```text
Program:   pwsh.exe
Arguments: -NoProfile -File "C:\path\to\Sync-CopilotAgents.ps1" -TenantId <tenant> -ClientId <appId> -CertificateThumbprint <thumbprint> -SiteUrl https://contoso.sharepoint.com/sites/Governance -ListName "Copilot Agents"
```

Set the task to run whether or not the user is logged on, under an account that has access to the certificate's private key.

---

## How it works

1. `New-CopilotAgentList.ps1` connects to SharePoint app-only, creates the list if it does not exist, and adds any missing columns from its schema definition (skipping ones that already exist). It then applies the column formatting JSON to the relevant columns.
2. `Sync-CopilotAgents.ps1` acquires a Graph token from the same app-only connection, lists Copilot packages from the **Graph v1.0** Package Management API (following pagination), and excludes first-party and third-party agents. It filters completed agents when resuming, then fetches details and resolves principals in bounded batches. Each batch is upserted sequentially over the single PnP connection (matched on `Agent Id`), checkpointing each successful write. The Graph token is requested again at each batch boundary. Transient Graph failures are retried, and blank fields are dropped so a re-sync never clears existing data.

---

## Known limitations

- Owner and shared-with resolution depends on the directory object still existing. Confirmed directory 404s are logged, skipped, and cached for the run. Other lookup errors fail that agent so incomplete enrichment is not checkpointed as successful.
- Package enumeration still follows every continuation page before detail batching begins; `-MaxAgents` limits enrichment and writes, not package enumeration. The service may return more records than the requested page size.
- Resume is for recovering an interrupted run, not a substitute for scheduled full refreshes: directory membership and other metadata may change without changing a package modification timestamp.
- Graph detail lookups run in parallel (`-ThrottleLimit`), but SharePoint writes are sequential, so very large tenants will still spend most of their time on the write phase.

---

## References

- [Microsoft Graph Package Management API](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/overview)
- [PnP.PowerShell](https://pnp.github.io/powershell/)
- [SharePoint list column formatting](https://learn.microsoft.com/en-us/sharepoint/dev/declarative-customization/column-formatting)
- [Agent Sync SharePoint (Flow) sample](../agent-sync-sharepoint/)
- [Catalog Connector sample](../catalog-connector/)

---

## Licence

MIT — see [LICENSE](../../LICENSE) for details.

> **Note:** This sample is community-maintained and is not covered by a Microsoft support SLA.
