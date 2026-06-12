# Aether Federated 360 Demo

This repo contains a minimal Salesforce DX app for an Account-level federated 360 view. It combines:

- Native CRM relationship context from Salesforce
- Virtual fulfillment context from an ERP mock
- Virtual financial context from a Billing mock

The implementation is designed for strategic account managers and executive leadership who need high-context data before high-stakes decisions.

## What is Included

- `Account.Global_UUID__c` custom field metadata
- `Account.Account_Tier__c` custom field metadata for Gold/Silver/Bronze segmentation
- `AetherFederatedController` Apex controller with named-credential callouts
- `AetherFederatedControllerTest` with callout mocks
- `aetherFederated360` record-page LWC with tabs for Sales, Operations, and Finance
- Child LWCs for the Operations and Finance views
- `Aether_Federated_Demo` permission set

## Project Structure

- `force-app/main/default/classes`
- `force-app/main/default/lwc`
- `force-app/main/default/objects/Account/fields`
- `force-app/main/default/permissionsets`

## Org Setup

### 1. Postman Mock Servers

Create two Postman mock endpoints:

- ERP mock:
  - `GET {{url}}/erp/customer/AETHER-LED-99`
  - Body:

```json
{
  "production_status": "Assembling",
  "chip_type": "High-Efficiency Blue",
  "current_production_batch": "BATCH-2048",
  "quality_control_status": "Passed",
  "shipping_eta": "2026-04-15",
  "warehouse_location": "Atlanta DC"
}
```

- Billing mock:
  - `GET {{url}}/finance/customer/AETHER-LED-99`
  - Body:

```json
{
  "credit_limit": 50000,
  "balance_due": 1250,
  "dso": 18,
  "payment_history": "On-time"
}
```

### 2. Named Credentials

Create two named credentials in Salesforce Setup:

- `Aether_ERP`
- `Aether_Billing`

Point them at the Postman mock base URLs. The Apex controller uses:

- `callout:Aether_ERP/erp/customer/{uuid}`
- `callout:Aether_Billing/finance/customer/{uuid}`

### 3. Deploy

```bash
sf project deploy start --source-dir force-app
```

### 4. Assign Permissions

```bash
sf org assign permset --name Aether_Federated_Demo
```

### 5. Seed Demo Data

Create an Account like:

- Name: `Aether LED`
- Global UUID: `AETHER-LED-99`
- Account Tier: `Gold`

Optional related records for a stronger Sales tab:

- Open Opportunities
- Open Cases
- Tasks / Events for activity history

## Record Page Composition

For the live demo, configure the Account Lightning Record Page like this:

- Highlight Panel (top): Account Name, `Global_UUID__c`, optional health score formula
- Left column: standard Record Detail
- Right column tabs:
  - Sales: standard related lists for Opportunities / Quotes / Cases
  - Operations: `aetherFederated360`
  - Finance: `aetherFederated360`

If you want a single custom panel instead of separate tabs, place only `aetherFederated360` on the page. The component already renders Sales, Operations, and Finance tabs internally.

## Executive Demo Scenarios

### 1. Global Neon Inc

- CRM: `$2M` pipeline
- Billing: `90 days overdue`

Decision: hold the deal until finance risk is cleared.

### 2. City Light Utilities

- CRM: `Silver`
- ERP: `Production Halted`

Decision: proactive account outreach before the client escalates.

### 3. Eco-Smart Warehousing

- Billing: `Zero balance / high credit`
- ERP: `50,000 units ready`

Decision: approve an acceleration offer or bulk discount.

## Notes

- The component uses Apex `@AuraEnabled(cacheable=true)` because the view is read-heavy.
- The data is federated on demand rather than copied into a golden record.
- This is intentionally optimized for low-volume, high-value users rather than call-center scale.

sf data import tree --files data/Account-Contact.json --target-org my-scratch-org
