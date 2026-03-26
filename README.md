# copilot-agent-inventory-samples

A collection of sample solutions that demonstrate what is possible with the **Microsoft Graph Copilot Admin Catalog (Inventory) API** — a beta API that gives tenant admins programmatic access to the Copilot agents deployed in their organisation.

Each sample targets a different platform or persona and is designed as a **reference implementation and starting point**, not a production-ready solution.

---

## The API

All samples in this repository are built on the [Microsoft Graph Copilot Admin Catalog API](https://learn.microsoft.com/graph/api/resources/copilot-overview) (`/beta/copilot/admin/catalog/packages`). This API exposes a catalog of Copilot packages available in a tenant, including agents built with Agent Builder, Copilot Studio, and first- and third-party agents.

Common capabilities unlocked by the API include:

- Listing all Copilot agents available in a tenant
- Retrieving detailed metadata for a specific agent (build type, deployment scope, owner, etc.)
- Identifying duplicate, orphaned, or underused agents
- Supporting governance workflows such as attestation and lifecycle management

---

## Samples

| Sample | Platform | Description |
| --- | --- | --- |
| [Agent Steward](samples/agent-steward/) | Microsoft 365 Copilot (Declarative Agent) | A conversational agent for IT admins to discover, analyse, and govern Copilot agents — with a focus on identifying duplicates and surfacing org-wide consolidation opportunities. |
| [Attestation](samples/attestation/) | Microsoft Power Platform | A Power Automate-based solution that retrieves agent inventory from the API, stores it in SharePoint or Dataverse, and drives attestation and lifecycle management workflows. |

---

## Contributing

Contributions are welcome. If you have built something on top of the Copilot Admin Catalog API and want to share it as a sample, open a pull request with your solution in a new folder under `samples/`.

Please include a `README.md` in your sample folder that covers what it does, prerequisites, and how to deploy it.

---

## Licence

MIT — see [LICENSE](LICENSE) for details.

> **Note:** These samples are community-maintained and are not covered by a Microsoft support SLA.
