---
name: bulk-action-plan
description: Turn a broad governance intent (e.g. "block every agent shared with the whole org that hasn't been reviewed" or "move all Finance agents to the Finance group") into a reviewable action plan file the admin approves BEFORE anything is executed. Use when the admin wants to act on many agents at once and needs to check the plan first.
status: draft
---

# bulk-action-plan

## When to use

Trigger when a request implies a change across **multiple** agents at once — *"block all …"*, *"reassign every … to …"*, *"clean up the agents that …"*. For a single, unambiguous agent, use the existing action functions directly instead.

## Inputs

- The `Agents` inventory (knowledge source) to resolve which agents match the intent.
- The API plugin to read current state (`warden_GetAgentDetail`) and to resolve people/groups (`warden_SearchUsers`, `warden_SearchGroups`) so the plan shows names, not just ids.

## What it does (runs code)

1. Interpret the intent and select the matching agents from the inventory.
2. Using CodeInterpreter, write **`action-plan.csv`** with one row per proposed change:

   | Column | Meaning |
   |---|---|
   | `AgentId` | The agent's `Agent Id` |
   | `Name` | Display name |
   | `Action` | `block` / `unblock` / `reassign-availability` / `reassign-deployment` |
   | `CurrentState` | Resolved before-state (blocked flag, or current audience names) |
   | `ProposedState` | Resolved after-state |
   | `Approved` | Left blank for the admin to mark `yes` / `no` |

3. Present the plan and ask the admin to review and edit it (they can change `Approved`, remove rows, or re-upload an edited file).
4. Only after explicit approval, execute the approved rows **one action at a time** through the existing functions, following the confirmation and write-back rules, and record each result (hand off to the `change-log` skill).

## Outputs

- `action-plan.csv` (created for review; the admin may edit and return it).

## Notes / constraints

- The plan file is a **proposal**. Generating it performs **no** writes.
- High-impact actions (block, removing everyone's access) must still be called out explicitly and confirmed.
- Reassignments replace the whole audience collection, so `ProposedState` must show the full intended set, not just additions.

## Status

Draft stub — not yet referenced by the agent.
