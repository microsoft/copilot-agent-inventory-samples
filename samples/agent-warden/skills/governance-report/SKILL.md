---
name: governance-report
description: Generate a downloadable governance report of the custom-agent inventory — counts by agent type and owner, currently blocked agents, agents available or deployed to everyone, and potential duplicates — as both a readable Markdown summary and a CSV for further analysis. Use when an admin asks for an inventory summary, a "state of governance" overview, or an exportable report.
status: draft
---

# governance-report

## When to use

Trigger when the admin asks for a summary or export of the inventory, e.g. *"give me a governance report"*, *"summarise the agents and export it"*, *"which agents are blocked or shared with everyone — put it in a file"*.

Do **not** trigger for a single-agent lookup or for taking an action; those use the existing plugin functions.

## Inputs

- The `Agents` SharePoint inventory (knowledge source) for the full list: name, `Agent Id`, agent type, owner, blocked status, availability, deployment, description.
- The connected **Insights Agent** for usage and adoption figures (active users, responses sent, last activity) per agent, matched to inventory rows by `Agent Id`.
- Optionally the API plugin (`warden_GetAgentDetail`) to confirm live state for any agent the report flags.

## What it does (runs code)

Using the CodeInterpreter capability, build two files from the inventory rows:

1. **`governance-report.md`** — a readable summary with sections:
   - Totals: agent count, grouped by agent type and by owner.
   - Blocked agents (name + `Agent Id`).
   - Broadly scoped agents where `AvailableTo` or `DeployedTo` = `all`.
   - Potential duplicates: agents sharing a similar name/description/purpose, grouped by theme. When usage data from the Insights Agent is available, classify severity (active vs. dormant) and include active-user/response figures.
2. **`governance-report.csv`** — one row per agent with columns: `AgentId, Name, Type, Owner, Blocked, AvailableTo, DeployedTo, ActiveUsers, ResponsesSent, LastActivity` for the admin to sort/filter in Excel (usage columns populated from the Insights Agent where available).

## Outputs

- `governance-report.md`
- `governance-report.csv`

Both are for review/download only — producing them takes **no** governance action.

## Notes / constraints

- Usage and adoption data comes from the connected Insights Agent. Use it to classify duplicate severity and adoption, but do not invent figures where the Insights Agent returns none — mark those as unavailable.
- Keep findings as observations; recommendations (block / consolidate) are suggestions the admin confirms via the normal write flow.

## Status

Draft stub — not yet referenced by the agent.
