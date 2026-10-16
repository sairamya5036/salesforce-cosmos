# CasePulse implementation and demo runbook

Target: **agOrg** (`sairamya945641@agentforce.com`). Work stays local; the owner handles Git push.

## 1. Check prerequisites

- [x] Inspect the Salesforce DX scaffold (API 68.0).
- [x] Select the intended development org. `agsf` was rejected by the owner; no deployment was made there.
- [x] Use Node 22 (`nvm use 22`) rather than the shell's Node 14 default.
- [x] Install a project-local Salesforce CLI; the original global CLI cannot recognize HXL bundles.
- [x] Confirm `McpServerDefinition` and `LightningTypeBundle` discovery in `agOrg`.
- [x] Enable the HXL beta in Setup (owner completed this), then successfully deploy `UiWidgetBundle`, both Lightning Types, and the MCP resource.

```sh
nvm install
nvm use
npm ci
npx sf org list
```

Do not print or commit JSON authentication output: some CLI commands include access tokens. Never retrieve global OAuth secrets into tracked source.

## 2. Deploy and test the core

**Completed in `agOrg`.** See [verification evidence](docs/verification.md) for deployment IDs and test results.

```sh
npx sf project deploy start --manifest manifest/core.xml --target-org agOrg --test-level NoTestRun --wait 10
npx sf apex run test --class-names CasePulseTests --target-org agOrg --code-coverage --result-format human --wait 10
```

The core contains Case fields, an explicit manager permission, one queue, Apex, a read-only preparation Flow, and a confirmation Screen Flow. Existing user profiles must provide Case read/update, EmailMessage read, and Task create access; CasePulse permission sets do not grant broad record visibility. Milestone reads use user mode and fail closed on missing field access.

## 3. Assign personas and support scope

```sh
npx sf org assign permset --name CasePulse_User --target-org agOrg
npx sf org assign permset --name CasePulse_Manager --target-org agOrg
npx sf apex run --file scripts/apex/seed-demo.apex --target-org agOrg
npx sf apex run --file scripts/apex/seed-cases.apex --target-org agOrg
```

**Completed:** both permission sets were assigned to the demo manager account; queue membership and six fictional cases were seeded. Do not rerun case seeding in that org.

Assign only `CasePulse_User` to a separate rep user. Managers also receive `CasePulse_Manager`. In Setup → Queues → CasePulse Support, add direct user members. Nested groups/roles are intentionally excluded. Sharing still applies: queue membership alone does not grant managers access to member-owned cases. Configure appropriate Case sharing for the demo.

The two seed commands are separate transactions because queue membership is setup DML. They insert six fictional cases and one synthetic outgoing email. Re-running case seed aborts to avoid duplicates. Deadline clocks start when seed runs; do not alter real cases to improve screenshots.

## 4. Deploy the experience and server

```sh
npx sf project deploy start --manifest manifest/experience.xml --target-org agOrg --wait 10
```

If a beta metadata type is rejected, preserve the error and record the dependency. Do not replace HXL with an LWC or claim a local preview is a verified client render.

In Setup → API Catalog → MCP Servers:

1. Open **CasePulse AI** (create it only if deployment did not create it).
2. Verify two tools: `analyzeCaseRisk` → Apex `CaseRiskAnalyzer`; `prepareCaseRescue` → Flow `CasePulse_Prepare_Rescue`.
3. The Flow API Catalog identifier must match the actual catalog asset. If the org rejects the source convention, add the Flow in Setup, retrieve this one server, and preserve the analysis widget resource.
4. Never add `CaseRescueApply` as an MCP tool.
5. Activate the server and copy its actual endpoint. Do not assume the production endpoint works for a sandbox.

The deployed Flow API identifier is `fa:flow-CasePulse_Prepare_Rescue`; Apex uses `aa:apex-CaseRiskAnalyzer`.

The HXL resource must point to `ui://widget/lightningType/c__analyzeCaseRisk`. Only the outer Lightning Type carries `renderer.json`.

## 5. Configure one External Client App

**Completed:** the CasePulse app registration and shared OAuth settings were deployed in `agOrg`; Claude and Slack callbacks use the same client registration. Do not create a second app. For another org, deploy `manifest/auth.xml`, then use `python3 scripts/python/prepare_oauth.py` to stage secret-free OAuth settings in `/tmp/casepulse-oauth`; deploy that isolated project. Configure the existing app in Setup → External Client App Manager.

1. Enable OAuth and register Claude's callback: `https://claude.ai/api/mcp/auth_callback`.
2. Add the exact callback shown by the Slack app's Manual OAuth configuration to this same app when connecting Slack.
3. Grant **Access MCP servers (`mcp_api`)** and **Perform requests at any time (`refresh_token`)**. Avoid `full` scope.
4. Enable JWT-based access tokens for named users. Follow Salesforce's current hosted MCP setup for the chosen client's PKCE/client-secret compatibility; do not copy desktop settings blindly into Slack.
5. Keep client credentials in the client UI or a local secret store. Never add keys or secrets to the README, screenshots, or tracked metadata.
6. Allow up to 30 minutes for registration to propagate.

Salesforce's global OAuth metadata contains secrets and is deliberately ignored by Git. See the official [External Client App instructions](https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/create-external-client-app.html).

## 6. Connect Claude Free

**Confirmed by the owner:** Claude connected and invoked `analyzeCaseRisk`, returning the correct six-case dataset and risk totals. Its first response was a text table. The owner then confirmed that a fresh conversation with an explicit request for the interactive app rendered the HXL console.

1. Sign in to the intended Salesforce org in the browser and sign out of unrelated Salesforce orgs.
2. In Claude → Customize/Settings → Connectors, add a custom remote connector named **CasePulse AI** using the activated Salesforce server endpoint.
3. Enter the External Client App client ID in the connector's advanced OAuth configuration if requested. Complete per-user Salesforce OAuth.
4. Claude Free supports one custom remote connector; remove an unused connector if the slot is occupied.
5. Ask: **“Use analyzeCaseRisk with view MY and demoOnly true to show cases that need immediate attention.”**
6. Verify the HXL widget renders, tool data matches Salesforce, and the client identifies the authenticated persona.
7. Ask: **“Prepare a rescue for case [number].”** Open the returned link, verify the case, check the approval box, and continue.
8. Verify `IsEscalated` and exactly one follow-up Task in Salesforce. A successful prepare tool call alone is not an escalation.

## 7. Connect Slack to the same server

1. Use a workspace with Slackbot MCP client access; for development, follow the [Slack Salesforce sandbox workshop](https://slack.dev/workshops/bringing-salesforce-flow-logic-into-slack-with-a-custom-mcp-server/).
2. Create a Slack app from [config/slack-app-manifest.example.json](config/slack-app-manifest.example.json). Replace the client ID, My Domain, and displayed server URL in a private copy. It uses Manual OAuth, `use_pkce: true`, `mcp_api` and `refresh_token`, and the existing External Client App. The `mcp_` provider prefix allows identity mapping to be omitted; Salesforce still authenticates each user.
3. Add `https://oauth2.slack.com/external/auth/callback` to the existing Salesforce app's callback list, retaining the Claude callback. Verify the current Slack UI still shows that address. Configure credentials privately and install the Slack app. Complete any workspace admin approval.
4. In Slackbot → Apps, connect CasePulse as the intended Salesforce user.
5. Verify tool discovery, risk analysis, and the Salesforce approval link.
6. Record actual rendering. Salesforce currently states that HXL does not render through Slackbot's Block Kit path. Do not promise identical visuals.

Guide: [Slackbot MCP client](https://docs.slack.dev/ai/slackbot-mcp-client/).

## 8. Capture genuine evidence

**Completed:** native HXL Playground manager/rep previews and actual Salesforce approval/success captures. Their provenance is documented in [docs/screenshots/README.md](docs/screenshots/README.md). Live Claude and Slack captures remain pending client authentication.

Save screenshots in `docs/screenshots/` after verification:

- `manager-console.png`: actual HXL team view in Claude.
- `rep-queue.png`: actual HXL MY view using a rep identity.
- `approval.png`: Salesforce confirmation screen with the proposed case changes.
- `rescue-success.png`: successful confirmation plus the Salesforce case/Task evidence.
- `slack-tools.png`: optional Slack tool result.

Exclude OAuth screens, credentials, and real customer data. Local fixture previews, if present, must retain their visible preview label and must not be presented as live integration evidence.

## 9. Two-minute demo

1. **0:00–0:25:** State the support-manager problem and ask for immediate-attention cases.
2. **0:25–0:50:** Explain a top-ranked case using visible deterministic reasons and the labeled deadline source.
3. **0:50–1:10:** Show the rep scope; explain that manager permission and sharing are enforced server-side.
4. **1:10–1:40:** Prepare rescue, open Salesforce, review, explicitly approve.
5. **1:40–2:00:** Show the escalation flag and one follow-up Task; repeat preparation to explain duplicate prevention.

## 10. Prepare for your Git push

```sh
npm run check:metadata
npm run prettier:verify
```

Review `docs/verification.md` for actual evidence and limitations. Initialize Git locally if desired; this scaffold originally had no `.git` folder. The assistant does not push, publish, or create a remote repository.

### Claude returns a table instead of the widget

**Resolved during live verification:** the first call returned correct case data but a text table; the owner confirmed interactive rendering in a fresh conversation. Start a fresh conversation with CasePulse enabled and explicitly ask to display the interactive HXL app. If needed, reconnect the connector after server metadata updates. Confirm the deployed `uiResource` and resource URI, then inspect actual MCP `tools/list` and `resources/read` metadata before assuming it is a styling problem. Native Playground rendering is verified separately. See [Claude interactive connector troubleshooting](https://support.claude.com/en/articles/13454812-use-interactive-connectors-in-claude).

### Approval screen shows HTML tags

Open a fresh approval link after deployment; an already-running Flow interview can retain its previous version. Screen rich text is stored in CDATA to preserve HTML through formatting. `npm test` validates the markup, and the browser verification requires actual rendered heading elements.
