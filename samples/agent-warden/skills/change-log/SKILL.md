---
name: change-log
description: Maintain a running audit trail of every governance action Warden performs. After each successful block/unblock/reassign, append a row to a change-log file capturing the agent, the action, the before/after state, and a timestamp. Use to keep a reviewable record and to satisfy "what changed and when" questions.
status: draft
---

# change-log

## When to use

Invoke immediately **after** any successful governance write (block, unblock, reassign availability/deployment, reassign owner), and whenever the admin asks *"what changes have been made"* or wants an exportable audit trail.

## Inputs

- The outcome of the action just performed (agent id + name, action, resolved before/after audience or blocked flag).
- An existing `warden-change-log.csv` if one has already been produced in the session, so new rows are appended rather than overwriting.

## What it does (runs code)

Using CodeInterpreter, create the log on first use or **modify the existing file** on subsequent actions, appending one row:

| Column | Meaning |
|---|---|
| `Timestamp` | UTC time the action completed |
| `AgentId` | The agent's `Agent Id` |
| `Name` | Display name |
| `Action` | The action taken |
| `Before` | Resolved prior state (blocked flag or audience names) |
| `After` | Resolved new state |
| `Result` | `succeeded` / `failed` |
| `ListSynced` | Whether the inventory-list write-back succeeded |

## Outputs

- `warden-change-log.csv` (created once, then appended in place across the session).

## Notes / constraints

- Only log an action **after** the Package Management write returns success — never pre-emptively.
- If the inventory-list write-back failed, record `ListSynced = no` so the discrepancy is visible.
- This skill records history; it does not perform or retry governance actions.

## Status

Draft stub — not yet referenced by the agent.
