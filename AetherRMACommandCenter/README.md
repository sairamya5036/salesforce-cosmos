# Aether RMA Command Center

Aether RMA Command Center is a Salesforce Service Cloud build for component-level return merchandise authorization. It gives support agents a guided console experience for diagnosing failed assets, selecting affected contract line items, and routing the correct outcome: repair, replacement, upsell, or refund.

The project is intentionally modeled around enterprise hardware service operations, where replacing an entire asset is often more expensive and less auditable than acting on the failed component. The design separates the customer-facing Case from downstream support actions by creating `Aether_Support_Product__c` records that preserve the service lifecycle, product relationship, and reporting trail.

## Why It Matters

This build demonstrates more than a screen flow. It shows how Salesforce can coordinate service execution, financial controls, and lifecycle reporting in one operating model:

- Agents work from a single RMA command surface instead of hopping between Case, Asset, Contract, and Product records.
- Contract line items provide component-level context, allowing service teams to act on the failed part rather than the whole installed asset.
- Refund decisions are governed by a dedicated approval flow with manager, director, and finance checkpoints.
- A custom support item object captures repair and replacement actions separately from the Case, enabling long-term analysis of product failure rates.
- The console app, layouts, path assistant, record type, queues, flows, and permissions are packaged as deployable metadata.

## Core Feature

The centerpiece is the **Aether RMA Command Center** screen flow. It is designed to launch from a Case and guide the agent through a high-value service decision.

The flow retrieves the current Case, identifies related contract line items for the asset under service, and presents the agent with action paths for repair, replacement, upsell, and refund. The decision path then drives persistence:

- **Repair** creates Aether Product Support Item records for the selected failed components.
- **Replacement** creates Aether Product Support Item records with replacement lifecycle tracking.
- **Upsell** creates an Opportunity for commercial follow-up when replacement is no longer the best service motion.
- **Refund** updates the Case with refund details and routes the request through approval governance.

The supporting approval flow handles refund thresholds and risk conditions, including manager approval for lower-value refunds, director review for hazard or higher-value cases, and finance sign-off before final resolution.

## Architecture Highlights

- **Console app:** `Aether_Service_Console` provides a focused Service Console shell with Case, Asset, Account, Contact, Service Contract, reports, and dashboards.
- **Case process:** `Case.Aether_RMA` record type and `AetherRMA` business process define the RMA lifecycle.
- **Guided UI:** `Aether_RMA` record page and `Aether_RMA` path assistant surface the RMA process directly on Case.
- **Automation:** `Aether_Refund_Process_New`, `Aether_Refund_RMA_Approval`, and `Update_Case_Status` coordinate agent action, approval governance, and Case status updates.
- **Service action object:** `Aether_Support_Product__c` stores repair and replacement work items with Case and Asset relationships.
- **Component diagnostics:** Contract Line Item fields such as `Inspection_Status__c`, `Product_Name__c`, `RootAssetId__c`, and `ServiceContract__c` support component-level triage.
- **Financial controls:** Case fields such as `Refund_Amount__c`, `Refund_Reason__c`, `Diagnosis__c`, `PotentialLiability__c`, and `SLAViolation__c` support refund decisions and auditability.
- **Access model:** `aethercommandcenter` permission set grants the app, object, field, record type, and system permissions needed to run the command center.

## Metadata Included

Key metadata in this repo:

- Custom application: `Aether_Service_Console`
- Permission set: `aethercommandcenter`
- Custom object: `Aether_Support_Product__c`
- Case record type and business process: `Aether_RMA`
- Flows: `Aether_Refund_Process_New`, `Aether_Refund_RMA_Approval`, `Update_Case_Status`
- Path assistant: `Aether_RMA`
- Flexipages: `Aether_RMA`, `Aether_Service_Console_UtilityBar`
- Queue: `AetherRMAApprovalQueue`
- Layouts for Account, Asset, Case, and Contract Line Item
- Runtime data plan: `aether_import_phase2_runtime.json`

## Deploy

Authenticate to the target org and set it as the default org:

```bash
sf org login web --set-default
```

If the org is already authenticated, verify the active default:

```bash
sf org display
```

Deploy the project metadata:

```bash
sf project deploy start --manifest manifest/package.xml
```

For a named org alias, use:

```bash
sf project deploy start --manifest manifest/package.xml --target-org YOUR_ORG_ALIAS
```

Assign the permission set to the current default org user:

```bash
sf org assign permset --name aethercommandcenter
```

For a named org alias, use:

```bash
sf org assign permset --name aethercommandcenter --target-org YOUR_ORG_ALIAS
```

## Load Runtime Data

Run the data load in this order. Phase 1 creates the base demo records, the pricebook helper prepares standard pricebook entries, and Phase 2 loads the RMA runtime records that depend on those earlier records.

```bash
sf data import tree --plan aether_import_test_data.json --target-org YOUR_ORG_ALIAS
```
```bash
node scripts/data/create_standard_pricebook_entries.mjs YOUR_ORG_ALIAS
```
```bash
sf data import tree --plan aether_import_phase2_runtime.json --target-org YOUR_ORG_ALIAS
```

The Phase 1 plan imports these JSON files:

- `data/aether_import_test_data/Pricebook2.json` - 1 custom Aether test pricebook
- `data/aether_import_test_data/Product2.json` - 20 products
- `data/aether_import_test_data/PricebookEntry.json` - 20 custom pricebook entries
- `data/aether_import_test_data/Account.json` - 1 account
- `data/aether_import_test_data/Contact.json` - 1 contact
- `data/aether_import_test_data/Asset.json` - 4 assets
- `data/aether_import_test_data/ServiceContract.json` - 2 service contracts

The pricebook helper reads the Phase 1 records from the target org, creates any missing Standard Price Book entries, resolves target-org IDs, and regenerates the Phase 2 runtime files used by the final import.

The Phase 2 plan then imports these JSON files:

- `data/aether_import_runtime/PricebookEntry.json` - 20 pricebook entries
- `data/aether_import_runtime/ContractLineItem.json` - 20 contract line items
- `data/aether_import_runtime/Entitlement.json` - 20 entitlements
- `data/aether_import_runtime/Case.json` - 4 RMA cases

Important: Phase 2 depends on Products, Assets, Accounts, Contacts, Service Contracts, Record Types, and Pricebooks created or resolved by the first two steps. Run the commands in order; do not run the Phase 2 import before the helper script regenerates the runtime JSON for the target org.

After import, validate the loaded RMA Cases:

```bash
sf data query --query "SELECT Id, Subject, Status, Refund_Amount__c, Refund_Reason__c FROM Case WHERE Subject LIKE 'RMA Request%' ORDER BY CreatedDate DESC LIMIT 10"
```

For a named org alias:

```bash
sf data query --query "SELECT Id, Subject, Status, Refund_Amount__c, Refund_Reason__c FROM Case WHERE Subject LIKE 'RMA Request%' ORDER BY CreatedDate DESC LIMIT 10" --target-org YOUR_ORG_ALIAS
```

## Demo Narrative

Start from an RMA Case in the Aether Service Console. The agent can review the lifecycle stage, inspect the related asset and contract line items, choose the appropriate service action, and let automation create the downstream records.

For senior technical audiences, emphasize these design choices:

- **Component-level RMA:** the solution acts on failed line items instead of treating the installed asset as one indivisible unit.
- **Separation of concerns:** the Case remains the customer service container, while `Aether_Support_Product__c` records track fulfillment work and lifecycle outcomes.
- **Governed refunds:** financial exposure is controlled through approval stages rather than embedded only in agent discretion.
- **Operational reporting:** repeated failures can be analyzed by product, asset, diagnosis, refund reason, and support action type.
- **Declarative-first architecture:** flows, record pages, layouts, pathing, queues, and permission sets make the solution inspectable and maintainable by Salesforce platform teams.

## Validation Checklist

After deployment and data load:

- Open the Aether Service Console.
- Confirm the current user has the `aethercommandcenter` permission set.
- Open an RMA Case using the `Aether_RMA` record type.
- Confirm the Aether RMA record page and path assistant are visible.
- Launch or inspect `Aether_Refund_Process_New`.
- Validate that repair and replacement paths create `Aether_Support_Product__c` records.
- Validate that refund paths update refund fields and enter approval routing.

## Stakeholder Summary

Aether RMA Command Center is a practical Service Cloud reference implementation for high-trust service operations. It combines agent productivity, component-level traceability, refund governance, and executive-grade reporting foundations in a deployable Salesforce DX project.
