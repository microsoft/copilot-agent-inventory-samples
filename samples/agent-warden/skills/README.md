# Agent Warden — candidate skills

> **Draft / exploration.** These are *candidate* skills we could add to Agent Warden to take advantage of the declarative-agent **skills** functionality. Nothing here is wired into the agent manifest yet — each folder is a design stub for review.

Agent Warden governs custom Copilot agents (block / unblock, reassign availability & deployment, write results back to the `Agents` SharePoint list). With the **CodeInterpreter** capability now enabled, skills can go beyond chat text and **run code to create and modify files** — reports, action plans, audit trails — that the admin can download, review, edit, and re-upload.

## Why file-producing skills fit Warden

Governance is a review-and-approve workflow. Producing a concrete artifact (a CSV of proposed changes, a Markdown report, a running change log) gives the admin something to inspect *before* Warden takes an irreversible action, and a record *after*.

## Candidate skills

| Skill | Purpose | Produces / modifies |
|---|---|---|
| [governance-report](governance-report/SKILL.md) | Summarise the inventory: counts by type/owner, blocked list, broadly-scoped agents, potential duplicates. | `governance-report.md` + `governance-report.csv` |
| [bulk-action-plan](bulk-action-plan/SKILL.md) | Turn a governance intent into a reviewable action plan the admin approves before execution. | `action-plan.csv` (created, then edited on approval) |
| [change-log](change-log/SKILL.md) | Maintain an audit trail of every block/unblock/reassign Warden performs. | `warden-change-log.csv` (appended in place) |

## Conventions for these drafts

- Each skill lives in its own folder with a `SKILL.md` describing **when to use it**, **inputs**, **outputs (files)**, and **the code it runs**.
- Skills read inventory from the same sources the agent already uses (the `Agents` SharePoint knowledge source; the API plugin for live state) — they do not introduce new data sources.
- File outputs are for **human review**. A skill never executes a governance write as a side effect of producing a file; the existing confirmation + write-back rules in [instruction.txt](../appPackage/instruction.txt) still apply.

## Status

Design stubs only. Next steps once we settle on scope: pick 1–2 to prototype, validate the file outputs against real inventory, then decide how to reference them from the agent.
