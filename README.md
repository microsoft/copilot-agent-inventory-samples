# Copilot Agent Inventory Samples

A collection of sample solutions that demonstrate what is possible with the **Microsoft Graph Package Management (Inventory) API** — a Microsoft Graph API that gives tenant admins programmatic access to manage Copilot agents deployed in their tenant.

**Please note - Access to the Package Management API requires a Microsoft Agent 365 license.**

Each sample targets a different platform or persona and is designed as a **reference implementation and starting point**, not a production-ready solution.

---

## The API

All samples in this repository are built on the [Microsoft Graph Package Management API](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/overview) (`/beta/copilot/admin/catalog/packages`). This API exposes a catalog of Copilot agents (packages) available in a tenant, including agents built with Agent Builder, Copilot Studio, Pro Dev Tools and 1P/3P agents.

Common capabilities unlocked by the API include:

- Listing all Copilot agents available in a tenant.
- Retrieving detailed metadata for a specific agent.
- Identifying duplicate, orphaned, or underused agents.
- Supporting governance workflows such as attestation and lifecycle management.

At the time of writing, the API supports delegated permissions only with application permissions planned.

---

## Samples

| Sample | Platform | Description |
| --- | --- | --- |
| [Agent Steward](samples/agent-steward/) | Microsoft 365 Copilot Declarative Agent | A declarative agent built with the M365 Agents Toolkit for IT admins to discover, analyse, and govern Copilot agents — with a focus on identifying duplicates, analysing usage and surfacing org-wide consolidation opportunities. |
| [Catalog Connector](samples/catalog-connector/) | Microsoft Power Platform | A Power Platform custom connector for the Microsoft Graph Package Management API. Import the included swagger file to use the connector in Power Automate flows, Power Apps, and Logic Apps to list, filter, and retrieve Copilot agent metadata from your tenant. |
| [Agent Sync SharePoint](samples/agent-sync-sharepoint/) | Microsoft Power Platform | A Power Automate flow (delivered as an unmanaged solution) that syncs your tenant's Copilot agent inventory to a SharePoint list, giving admins a familiar, filterable view of all agents. |
| [Attestation — COMING SOON](samples/attestation/) | Microsoft Power Platform | A Power Automate-based solution that retrieves agent inventory from the API, stores it in SharePoint or Dataverse, and drives attestation and lifecycle management workflows. |

---

## Contributing

Contributions are welcome. If you have built something on top of the Copilot Package Management API and want to share it as a sample, fork the repo, open a pull request with your solution in a new folder under `samples/`.

Please include a `README.md` in your sample folder that covers what it does, prerequisites, and how to deploy it.

---

## Licence

MIT — see [LICENSE](LICENSE) for details.

> **Note:** These samples are community-maintained and are not covered by a Microsoft support SLA.
