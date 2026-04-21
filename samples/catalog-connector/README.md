# Copilot Agent Catalog – Power Platform Custom Connector

> **This is a sample.** This connector is designed to showcase the art of the possible with the [Microsoft Graph Package Management (Inventory API)](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/resources/copilotpackagedetail). It is intended as a starting point and reference implementation, not a production-ready connector.

The **Copilot Agent Catalog** connector is a Power Platform Custom Connector that wraps the Microsoft Graph Package Management API. Once imported into your Power Platform environment, it can be used in **Power Automate flows**, **Power Apps**, and **Logic Apps** to programmatically access the Copilot agent inventory in your Microsoft 365 tenant — without writing any API integration code.

---

## What it does

The connector exposes two actions against the `/beta/copilot/admin/catalog/packages` endpoint:

| Action | Description |
| --- | --- |
| **Get Copilot Packages** | Returns a paged list of all Copilot agent packages available in the tenant. Supports OData `$filter`, `$top`, and `$skiptoken` for filtering and pagination. |
| **Get Package Detail** | Returns full metadata for a specific agent package by ID, including element details, allowed users and groups, acquisition scope, and version information. |

With these two actions you can build flows and apps that:

- **Inventory** all Copilot agents in your tenant on a schedule and store the results in SharePoint or Dataverse
- **Filter** agents by type, publisher, availability scope, or blocked status
- **Trigger governance workflows** based on catalog changes — for example, when a new agent appears or an existing one is blocked
- **Feed agent metadata into Power BI** or other reporting solutions via Power Automate
- **Drive attestation processes** by retrieving agent details and routing them to owners for review

---

## Prerequisites

- A Microsoft 365 tenant with [Microsoft 365 Copilot licences](https://learn.microsoft.com/microsoft-365-copilot/extensibility/prerequisites#prerequisites)
- Access to the Package Management API — requires **enrolment in the [Microsoft 365 Frontier program](https://aka.ms/m365frontier)** at the time of writing
- A **Power Platform environment** with permissions to create custom connectors (Environment Maker role or higher)
- An **Entra ID app registration** configured with the `CopilotPackages.Read.All` delegated permission
- The user account running flows with this connector must hold the **Global Administrator** or **AI Administrator** role — the API only supports delegated authentication at the time of writing, so calls are made as the signed-in user

---

## Setup and deployment

### 1. Create an Entra ID app registration

1. Go to the [Microsoft Entra admin centre](https://entra.microsoft.com) and sign in.
2. Navigate to **Identity** > **Applications** > **App registrations** and select **New registration**.
3. Give the app a name (e.g. `Copilot Agent Catalog Connector`) and set the supported account type to **Accounts in this organisational directory only**.
4. Under **Redirect URI**, select **Web** and enter the Power Platform consent redirect URL:
   ```
   https://global.consent.azure-apim.net/redirect
   ```
5. Select **Register**.
6. Navigate to **API permissions** > **Add a permission** > **Microsoft Graph** > **Delegated permissions**, search for `CopilotPackages.Read.All`, add it, and then **Grant admin consent**.
7. Navigate to **Certificates & secrets** > **New client secret**, enter a description, choose an expiry period, and copy the **Value** — you will need this in step 3.
8. Copy the **Application (client) ID** and **Directory (tenant) ID** from the app overview — you will also need these in step 3.

### 2. Import the connector into Power Platform

1. Go to [make.powerapps.com](https://make.powerapps.com) and select your target environment from the environment picker.
2. In the left navigation, select **More** > **Discover all**, then find and pin **Custom connectors**. Or navigate directly via **Data** > **Custom connectors** if available in your environment.
3. Select **+ New custom connector** > **Import an OpenAPI file**.
4. Enter a display name for the connector (e.g. `Copilot Agent Catalog`) and upload the [`CopilotPackages.swagger.json`](CopilotPackages.swagger.json) file from this folder.
5. Select **Continue** to open the connector editor.

### 3. Configure OAuth 2.0 authentication

On the **Security** tab of the connector editor:

1. Confirm that **Authentication type** is set to **OAuth 2.0**.
2. Set **Identity provider** to **Azure Active Directory**.
3. Fill in the following fields using the values from step 1:

   | Field | Value |
   | --- | --- |
   | Client ID | Application (client) ID from your app registration |
   | Client secret | Client secret value from your app registration |
   | Tenant ID | Directory (tenant) ID (or `common` for multi-tenant) |
   | Resource URL | `https://graph.microsoft.com` |

4. Ensure **Enable on-behalf-of login** is turned on.
5. Select **Create connector** to save.

### 4. Create a connection and test

1. Navigate to the **Test** tab in the connector editor.
2. Select **+ New connection** and complete the OAuth sign-in with an account that holds the Global Administrator or AI Administrator role. The connection will be saved to your environment.
3. Under **Test an operation**, select **Get Copilot Packages** and choose **Test operation**. A `200` response with a `value` array of packages confirms the connector is working correctly.

---

## Using the connector in Power Automate

Once the connector and a connection are created, they appear under **Custom** in the Power Automate action picker.

### Example: Daily inventory sync to SharePoint

1. Create a new **Scheduled cloud flow** with a daily recurrence.
2. Add the **Copilot Agent Catalog – Get Copilot Packages** action.
3. Add a **Parse JSON** action to extract the `value` array (use the schema from the connector's response definition).
4. Add an **Apply to each** loop over the items and use **SharePoint – Create item** to write each agent's details to a SharePoint list.

### Handling pagination

> **Note:** Pagination via `@odata.nextLink` / `$skiptoken` is not currently supported for this API endpoint under delegated authentication. This is expected to be resolved when application permissions are introduced. Until then, set `$top` to `999` in the **Get Copilot Packages** action to retrieve as many results as possible in a single call.

Once application permissions are available, pagination will work as follows: if the tenant has more packages than the page size, the response will include an `@odata.nextLink` value containing a `$skiptoken`. Use a **Do until** loop, passing the token back into the `$skiptoken` parameter on each iteration, to retrieve all pages before processing.

---

## References

- [Microsoft Graph Package Management API](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/overview)
- [Create a custom connector from an OpenAPI definition – Power Platform](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-openapi-definition)
- [Register an application in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [Microsoft 365 Copilot extensibility samples](https://learn.microsoft.com/microsoft-365-copilot/extensibility/samples)

---

## Licence

MIT — see [LICENSE](../../LICENSE) for details.

> **Note:** This sample is community-maintained and is not covered by a Microsoft support SLA.
