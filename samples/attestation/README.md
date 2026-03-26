# Copilot Agent Inventory – Power Platform Sample

> **This is a sample.**  
> This solution demonstrates how the **Copilot Inventory (Admin Catalog) API** can be used with **Microsoft Power Platform** to build lightweight governance, observability, and lifecycle management workflows for Copilot agents.  
>  
> It is intended as a **reference implementation and starting point**, not a production‑ready governance solution.

---

## Overview

**Copilot Agent Inventory – Power Platform Sample** shows how IT admins and platform teams can use **Power Automate, SharePoint, and (optionally) Power BI** to discover, track, and govern Copilot agents across a tenant.

The solution retrieves agent metadata from the **Microsoft Graph Copilot Admin Catalog API**, stores and enriches it in Power Platform data sources, and enables common governance scenarios such as attestation, lifecycle monitoring, and basic inventory reporting.

---

## What it does

- **Inventory**
  - Retrieve all Copilot agents from the tenant catalog using the Inventory API
  - Capture key metadata such as agent name, ID, owner, build type, and deployment scope

- **Persist & enrich**
  - Store inventory data in SharePoint lists or Dataverse
  - Enrich agent records with governance attributes (attestation status, review dates, notes)

- **Attestation workflows**
  - Automatically notify agent owners when new agents are detected
  - Collect attestations via Microsoft Forms
  - Track signed and expired attestations centrally

- **Lifecycle management**
  - Identify agents with missing or expired attestations
  - Support automated or manual follow‑up actions (for example reminders, escalation, or block)

- **Reporting & observability**
  - Provide admin‑level views of all agents
  - Enable downstream reporting in Power BI using SharePoint or Dataverse as a source

---

## Architecture (high level)

- **Microsoft Graph**
  - Copilot Admin Catalog (Inventory) API

- **Power Platform**
  - Power Automate for scheduled syncs and governance workflows
  - SharePoint lists or Dataverse for persistence
  - Microsoft Forms for attestations
  - Optional Power BI for reporting

---

## Prerequisites

- Microsoft 365 tenant with **Microsoft 365 Copilot** enabled
- Permissions to call the **Copilot Admin Catalog API**
- Power Platform environment with:
  - Power Automate
  - SharePoint (or Dataverse)
- An Entra ID app registration configured for Microsoft Graph access

---

## Setup and deployment

### 1. Import the Power Automate flows

1. Download the flows from the `/power-automate` folder.
2. Import each flow into your Power Platform environment.
3. Update connections for:
   - Microsoft Graph (HTTP with Azure AD)
   - SharePoint
   - Microsoft Forms

---

### 2. Configure the Entra ID app registration

1. Register an application in **Entra ID**.
2. Grant the required permissions for the Copilot Admin Catalog API.
3. Create a client secret or certificate.
4. Update the Power Automate HTTP actions with:
   - Tenant ID
   - Client ID
   - Secret or certificate reference

---

### 3. Set up data storage

Choose one of the following:

- **SharePoint**
  - Create lists for:
    - Agent inventory
    - Attestations
    - Review history

- **Dataverse (optional)**
  - Use tables if you want richer relationships or Power Apps integration

---

### 4. Configure attestations

1. Create a Microsoft Form for agent attestation.
2. Capture:
   - Agent ID
   - Agent name
   - Owner acknowledgement
3. Update the attestation flow to store responses in your chosen data store.

---

### 5. Schedule inventory sync

- Configure the inventory flow to run on a schedule (for example daily).
- The flow:
  1. Calls the Inventory API
  2. Upserts agent records
  3. Triggers governance logic (new agent, expired attestation, etc.)

---

## Project structure