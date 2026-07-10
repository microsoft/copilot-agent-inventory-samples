# Copilot Agent Inventory – SharePoint Sync

> **This is a sample.**
> This solution demonstrates how the **Microsoft Graph Package Management API** can be used with **Power Automate** to sync your tenant's Copilot agent inventory to a **SharePoint list** — giving IT admins a familiar, filterable, and shareable view of all agents without writing code.
>
> It is intended as a **reference implementation and starting point**, not a production-ready solution.

---

## Overview

This is an unmanaged Power Platform solution containing:

| Component | Description |
| --- | --- |
| **Power Automate flow** | A manually-triggered instant cloud flow that calls the Package Management API and creates an item in a SharePoint list for each Copilot agent. |

Once imported and configured, triggering the flow populates your SharePoint list with the current agent inventory, ready for filtering, reporting, or feeding into downstream governance processes.

---

## Prerequisites

- A Microsoft 365 tenant with [Microsoft 365 Copilot licences](https://learn.microsoft.com/microsoft-365-copilot/extensibility/prerequisites#prerequisites)
- Access to the Package Management API — requires an Agent 365 license.
- An **Entra ID app registration** configured for Microsoft Graph access with application permission:
  - `CopilotPackages.Read.All`
- Tenant-wide admin consent is required for this application permission. Least-privileged roles that can grant Microsoft Graph application-permission consent are **Privileged Role Administrator** and **Global Administrator**.
- A **Power Platform environment** with permissions to import solutions (Environment Maker role or higher).
- **Power Apps premium license** for the user account that creates and runs the flow, as this solution uses the HTTP with Microsoft Entra ID connector which requires premium licensing.
- The identity used by the **Inventory Sync Microsoft Entra ID HTTP Connection** (the preauthorized connector connection) must have delegated `Directory.Read.All` to resolve `sharedWithUsersAndGroups` via `directoryObjects/getByIds`. You can use a dedicated service account for this connection.
- A **SharePoint site** where you have permission to create lists.

---

## Setup and deployment

### 1. Create an Entra ID app registration

If you do not already have one, create an app registration that will be used by the flow's Microsoft Graph HTTP actions:

1. In **Microsoft Entra admin center** > **App registrations**, create a new app registration.
2. In **API permissions**, add Microsoft Graph **Application** permission:
   - `CopilotPackages.Read.All`
3. Select **Grant admin consent** for your tenant (using **Privileged Role Administrator** or **Global Administrator**).
4. In **Certificates & secrets**, create a new client secret and copy the value.
5. Note these values for step 4:
   - **Application (client) ID**
   - **Directory (tenant) ID**
   - **Client secret**

### 2. Create the SharePoint list

1. Navigate to your target SharePoint site.
2. Select **+ New** > **List** > **Blank list**.
3. Give the list a name (e.g. `Agents`) and select **Create**.
4. Add the following columns to the list. Select **+ Add column** or **Create column** for each:

   | Column name | Type |
   | --- | --- |
   | Short Description | Multiple lines of text |
   | Blocked | Yes/No |
   | Last Modified | Date and Time |
   | Agent Type | Choice |
   | Instructions | Multiple lines of text |
   | Long Description | Multiple lines of text |
   | Capabilities | Multiple lines of text |
   | Graph Connector Ids | Multiple lines of text |
   | Websites | Multiple lines of text |
   | Id | Single line of text |
   | Owner | Person or Group |
   | ODSP Sites | Multiple lines of text |
   | Suggested Prompts | Multiple lines of text |
   | Discourage Model Knowledge | Yes/No |
   | Available To | Single line of text |
   | Deployed To | Single line of text |
   | Shared With | Person or Group (Allow selection of groups) |

#### Configure the Agent Type choices

After creating the columns, add the choice values for the **Agent Type** column:

1. Select the **Agent Type** column header.
2. Select **Column settings** > **Edit**.
3. Under **Choices**, add the following values:
   - `Agent Builder`
   - `Copilot Studio`
   - `LOB`
   - `Unknown`
4. Select **Save**.

### 3. Apply column formatting

Apply the provided column formatting JSON to improve the visual appearance of key columns:

#### Capabilities column

1. In the SharePoint list, select the **Capabilities** column header.
2. Select **Column settings** > **Format this column**.
3. In the formatting pane, select **Advanced mode**.
4. Delete any existing content and paste the contents of [`column-formatting/capabilities.json`](column-formatting/capabilities.json).
5. Select **Save**.

This displays each capability (e.g. WebSearch, Email, OneDriveAndSharePoint) as a colour-coded pill/badge.

#### Graph Connector Ids column

1. Select the **Graph Connector Ids** column header.
2. Select **Column settings** > **Format this column**.
3. In the formatting pane, select **Advanced mode**.
4. Delete any existing content and paste the contents of [`column-formatting/graph-connector-ids.json`](column-formatting/graph-connector-ids.json).
5. Select **Save**.

This displays connector IDs as a styled badge when present, or a dash when the field is empty.

### 4. Import the Power Platform solution

1. Go to [make.powerautomate.com](https://make.powerautomate.com) and select your target environment.
2. Navigate to **Solutions** > **Import solution**.
3. Select **Browse** and upload the [`CopilotAgentInventorySync_1_0_0_1.zip`](CopilotAgentInventorySync_1_0_0_1.zip) file.
4. You will be prompted to set **Environment Variables**. Configure them as follows:

   | Variable | Value |
   | --- | --- |
   | **Inventory Sync SharePoint Site** | Select the SharePoint site where you created the list in step 2. |
   | **Inventory Sync Agents List** | Select the SharePoint list you created in step 2 (e.g. `Agents`). |
   | **Inventory Sync Tenant ID** | The Entra tenant ID from step 1. |
   | **Inventory Sync Client ID** | The Entra app registration client ID from step 1. |
   | **Inventory Sync Client Secret** | The client secret value from step 1. |

5. Select **Import**.

> **Security note:** The **Inventory Sync Client Secret** environment variable stores the app registration client secret in plain text. While the HTTP connector actions have been configured with secured inputs, for production deployments we recommend storing sensitive credentials in **Azure Key Vault** instead and retrieving them via managed identity or connector authentication. This sample is intended as a reference implementation.

### 5. Configure connections

After import, open the solution and ensure all connection references are mapped to active connections:

1. **Inventory Sync Microsoft Entra ID HTTP Connection**  
   Create/select a connection for **HTTP with Microsoft Entra ID**. This preauthorized connector uses the connection owner's delegated user permissions for calls such as `directoryObjects/getByIds` (this is used to resolve the 'shared with' user details), so ensure that user has delegated `Directory.Read.All` (or use a service account with this permission).
2. **Inventory Sync SharePoint Connection**  
   Create/select a connection for **SharePoint**.
3. **Inventory Sync Office 365 Users Connection**  
   Create/select a connection for **Office 365 Users**.

### 6. Run the flow

1. Navigate to the **Get Copilot Packages** flow within the solution.
2. Select **Run** to trigger a sync.

> **Note:** The flow run may report as failed if one or more agent owner IDs cannot be resolved to a user in your directory. Despite the failure status, agents that were processed before the error will still have been synced to the SharePoint list — only the agents where the owner could not be resolved will be missing. This is a known limitation and will be fixed in a future update.

---

## Screenshots

![Get Copilot Packages flow](flow-screenshot.png)

---

## How it works

1. The flow is triggered manually.
2. It calls Microsoft Graph package endpoints using app credentials from environment variables (`Tenant ID`, `Client ID`, `Client Secret`) with the HTTP connector, it uses the HTTP with Microsoft Entra ID (preauthorized) to resolve shared users/groups in the connection owner's delegated user context.
3. For each agent in the response, it creates a new item in the configured SharePoint list with the agent's metadata mapped to the list columns.

> **Note:** The flow creates new items on each run. It does not update or deduplicate existing entries. To maintain a clean list, clear existing items before re-running, or extend the flow with upsert logic as needed.

---

## Known limitations

- The flow creates new list items only — it does not update existing entries if an agent's metadata has changed.
- The flow may fail if an agent's owner ID cannot be resolved (see [Run the flow](#6-run-the-flow) note above).

---

## Suggested enhancements

The following are improvements you could make to extend this sample:

| Enhancement | Description |
| --- | --- |
| **Separate into parent/child flows** | Split the solution so a parent flow calls **Get Copilot Packages** and a child (sub) flow retrieves the detail for each agent. This allows the child flow to run with higher concurrency without hitting API rate limits on the list operation. |
| **Upsert logic** | Enhance the flow to check whether an agent already exists in the SharePoint list (by ID) and update the existing item rather than creating a duplicate. |
| **Increase concurrency** | Once separated into parent/child flows, increase the concurrency control on the child flow to process multiple agents in parallel. |
| **Scheduled trigger** | Replace the manual trigger with a scheduled recurrence (e.g. daily) to keep the inventory list automatically up to date. |

---

## Planned future enhancements

The following features are planned for future releases of this sample:

- **Teams notifications** — notify administrators via Teams when new agents are created or existing agents are modified.
- **Automated blocking** — automatically block agents that do not meet governance criteria (e.g. missing attestation, no owner).
- **Automated deletion** — remove or archive agents that are orphaned or unused beyond a defined period.
- **Owner resolution fix** — handle unresolvable owner IDs gracefully so the flow completes successfully for all agents.

---

## References

- [Microsoft Graph Package Management API](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/overview)
- [Import a Power Platform solution](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions)
- [SharePoint list column formatting](https://learn.microsoft.com/en-us/sharepoint/dev/declarative-customization/column-formatting)

---

## Licence

MIT — see [LICENSE](../../LICENSE) for details.

> **Note:** This sample is community-maintained and is not covered by a Microsoft support SLA.
