# Verification evidence

Verified October 16, 2026 against **agOrg**, selected by the owner. No code was pushed or published to Git hosting.

## Deployment

| Component                                                  | Status                             | Salesforce deployment ID |
| ---------------------------------------------------------- | ---------------------------------- | ------------------------ |
| Core Apex, tests, fields, permissions, queue and Flows     | Succeeded with ten specified tests | `0AfgK00000WjQATSA3`     |
| HXL widget, nested Lightning Types and complete MCP server | Succeeded                          | `0AfgK00000WjfJ8SAJ`     |
| Single External Client App registration                    | Succeeded                          | `0AfgK00000WjT9uSAF`     |
| Shared Claude/Slack OAuth plugin configuration             | Succeeded                          | `0AfgK00000WjsLBSAZ`     |

The owner enabled HXL beta after the initial org-level rejection. A read-only metadata retrieval subsequently confirmed that `CasePulse` retained `uiResource=casePulseConsole` and `ui://widget/lightningType/c__analyzeCaseRisk`. Flow registration uses `fa:flow-CasePulse_Prepare_Rescue`.

OAuth global settings were staged outside tracked source. The committed app header intentionally excludes credentials. The owner confirmed activation, connection to Claude, correct risk-tool results, and live interactive HXL rendering.

## Apex and metadata checks

**10 tests passed, 0 failures. CasePulse coverage: 93.7% (283/302 executable locations).** This is coverage for the project's classes and trigger, not org-wide coverage.

| Component              | Covered locations | Coverage |
| ---------------------- | ----------------- | -------: |
| CaseRescueApply        | 53/56             |    94.6% |
| CaseRescuePrepare      | 23/26             |    88.5% |
| CaseRiskAnalyzer       | 167/178           |    93.8% |
| CasePulseReopen        | 1/1               |   100.0% |
| CasePulseReopenHandler | 11/12             |    91.7% |
| CasePulseAccess        | 28/29             |    96.6% |

The suite covers exact risk boundaries, score capping, stale-email fallback and outgoing email integration, rep/team scope, invalid view requests, missing read permissions, denied Task creation with rollback, no approval, closed cases, repeated approval, result limits, empty state, reopen transitions, demo-only filtering, read-only Flow preparation, changed ownership between preparation and approval, and a 200-case bulk manager rescue.

Machine-readable results: [apex-verification.json](apex-verification.json).

`npm test` validates XML/JSON syntax, widget binding/field trace, nested renderer mapping, the two-tool read-only allowlist, approval wiring, Flow references, protected idempotency marker, and credential exclusion. `npm run prettier:verify` passed. Formatting explicitly disables embedded-language formatting so XML Flow names cannot be rewritten as JavaScript.

The actual REST invocable action endpoint was exercised: `actionName=CaseRiskAnalyzer`, `isSuccess=true`, `errors=null`, and `outputValues.console` matched the Lightning Type contract.

## Browser and visual verification

- Native Salesforce HXL Playground rendered the actual composition with `MY` and `TEAM` snapshots returned by deployed Apex. These are **preview screenshots**, not proof of a live Claude render.
- The actual Salesforce confirmation screen was opened and captured without approving its seeded case.
- A disposable fictional case was used to verify the entire Screen Flow: continuing without approval made no changes; simulated approval set the flag and created exactly one Task; a repeated approval left one Task. The test case and Task were then cleaned up.
- [approval-ui-verification.json](approval-ui-verification.json) records those results. Screenshot provenance is in [screenshots/README.md](screenshots/README.md).

## Live client status and remaining work

| Capability                           | Evidence/status                                                                                                                                                                |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Claude connection and risk tool call | Owner confirmed; correct six fictional cases and 2 Critical / 1 High / 2 Watch / 1 Healthy at the reported timestamp                                                           |
| Live Claude HXL rendering            | Owner confirmed the interactive console appears in a fresh conversation. The initial response was a text table; the successful retry explicitly requested the interactive app. |
| Live Claude rescue-preparation tool  | Owner confirmed the HXL Prepare rescue button returns a link to the correct Salesforce case approval screen                                                                    |
| Slack                                | Manifest template and PKCE setup documented; no workspace connection or live rendering verified                                                                                |
| Separate rep client identity         | Authorization verified in Apex with `System.runAs`; screenshot uses the demo manager account's explicit MY view                                                                |
| Real contractual milestone data      | Optional query implemented; the portfolio demonstration uses labeled synthetic deadlines                                                                                       |

## Tooling and boundaries

Node 22.19+ is required. Validation used Node 22.22.1 and the project-local Salesforce CLI 2.154.4; the original shell Node 14/global CLI combination cannot handle the HXL bundle.

The npm audit reports **61 advisories in the local development toolchain** (15 moderate, 45 high, 1 critical), including dependencies bundled by the Salesforce CLI. The `--omit=dev` report still includes some bundled CLI dependencies, so it is not reported as a clean runtime audit. Salesforce executes the deployed Apex/Flow/HXL metadata; this project deploys no Node service. Updating or replacing the CLI/toolchain is separate follow-up work; no forced breaking dependency upgrade was applied.

Analysis evaluates the oldest 500 accessible open cases and returns the top 20. The output explicitly states its evaluation and truncation limits. Repeated rescue approvals create one Task per case for this MVP; deleting that Task does not start a new rescue cycle.

## Approval rich-text correction

The owner confirmed that Claude's Prepare rescue button returned the correct Salesforce link. The opened screen exposed literal HTML after XML formatting inserted spaces in escaped tags. The four Screen Flow display blocks now use CDATA, which preserves their markup through formatting. Correction deployment: `0AfgK00000Wjq1fSAB`. Metadata checks reject malformed heading tags, and browser checks require actual heading elements before accepting a screenshot or success state.

After this correction, the live page passed the actual heading check. The complete disposable-case browser test passed again: cancel without changes, approve with one Task, and repeated approval without duplicates. Approval and success screenshots were refreshed.
