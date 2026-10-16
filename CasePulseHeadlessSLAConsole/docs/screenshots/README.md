# Screenshot provenance

All images were captured on October 16, 2026. No image generation or synthetic client chrome was used.

| Image                                          | Source                                                            | What it proves                                                                                                     |
| ---------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| [Manager console](manager-console-preview.png) | Official Salesforce HXL Playground, native Claude preview         | The actual widget composition renders with synthetic-only data returned by deployed Apex                           |
| [Rep layout](rep-queue-preview.png)            | Same native Playground, `MY` snapshot from the demo account       | The personal queue layout renders; this image alone does not prove a separate rep identity                         |
| [Approval](approval.png)                       | Deployed Salesforce Screen Flow in `agOrg`                        | The real case review and explicit approval controls are present; no approval was submitted for this screenshot     |
| [Success](rescue-success.png)                  | Same deployed Screen Flow, disposable synthetic browser-test case | The real success screen after automated checkbox approval; this is a test, not an actual human/customer escalation |

The browser test verified cancellation without changes, approved escalation with exactly one Task, and repeated approval without duplicates. Its disposable case and Task were removed afterward. Machine-readable evidence is in [approval-ui-verification.json](../approval-ui-verification.json).

The console fixtures are timestamped snapshots, not live subscriptions. Both snapshots were produced by the same manager account using explicit `MY`/`TEAM` views. Rep authorization is separately verified with `System.runAs` in Apex tests. All case subjects are fictional; the displayed owner is the project author's demo account.

**Owner-confirmed:** live Claude HXL rendering works in a fresh conversation.

**Pending:** genuine screenshots from connected Claude and Slack accounts. Playground previews intentionally retain their visible preview label. Do not rename them to imply a verified client connection.

Reproduce from the repository root with Node 22.19+ and Google Chrome installed:

```sh
npm run screenshots:hxl
npm run screenshots:approval
npm run test:approval-ui
```

The two Salesforce scripts use the explicit `agOrg` alias. Review or change that target before using them in another org. The browser verification command creates and deletes its own synthetic case/Task; the normal approval capture only reads an existing seeded demo case. Session URLs are kept in process memory and never written to source or screenshots.
