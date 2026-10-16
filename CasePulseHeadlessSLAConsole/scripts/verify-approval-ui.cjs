// Exercise the real Screen Flow on a disposable synthetic case, then clean it up.
// This simulates approval for testing; it is not an actual customer escalation.
const { chromium } = require("playwright");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const sf = process.cwd() + "/node_modules/.bin/sf";
const invoke = (args) =>
  JSON.parse(
    execFileSync(sf, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    })
  );
const common = ["--target-org", "agOrg", "--json"];
const query = (q) =>
  invoke(["data", "query", "--query", q, ...common]).result.records;
(async () => {
  let browser, caseId, page;
  try {
    caseId = invoke([
      "data",
      "create",
      "record",
      "--sobject",
      "Case",
      "--values",
      "Subject='[DEMO] Browser approval verification' Status='New' Origin='Web' Priority='High' CasePulse_Demo__c=true",
      ...common
    ]).result.id;
    const login = invoke(["org", "open", "--url-only", ...common]);
    browser = await chromium.launch({ channel: "chrome", headless: true });
    page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    await page.goto(login.result.url, {
      waitUntil: "domcontentloaded",
      timeout: 60000
    });
    await page.waitForURL(
      (url) => url.hostname.endsWith(".lightning.force.com"),
      { timeout: 60000 }
    );
    const url =
      new URL(login.result.url).origin +
      "/flow/CasePulse_Confirm_Rescue?caseId=" +
      caseId;
    const open = async () => {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });
      await page
        .getByRole("button", { name: "Continue", exact: true })
        .waitFor({ timeout: 30000 });
    };
    await open();
    await page.getByRole("button", { name: "Continue", exact: true }).click();
    await page
      .getByRole("heading", { name: "Rescue cancelled", exact: true })
      .waitFor({ timeout: 20000 });
    let c = query(`SELECT IsEscalated FROM Case WHERE Id='${caseId}'`)[0];
    if (c.IsEscalated) throw Error("Cancellation changed the case");
    const tasks = () => query(`SELECT Id FROM Task WHERE WhatId='${caseId}'`);
    if (tasks().length !== 0) throw Error("Cancellation created a task");
    await open();
    await page.getByRole("checkbox").focus();
    await page.keyboard.press("Space");
    await page.getByRole("button", { name: "Continue", exact: true }).click();
    await page
      .getByRole("heading", { name: "Rescue recorded", exact: true })
      .waitFor({ timeout: 20000 });
    await page.screenshot({
      path: "docs/screenshots/rescue-success.png",
      clip: { x: 0, y: 0, width: 1280, height: 400 }
    });
    c = query(
      `SELECT IsEscalated,CasePulse_Rescue_Task__c FROM Case WHERE Id='${caseId}'`
    )[0];
    if (!c.IsEscalated || !c.CasePulse_Rescue_Task__c || tasks().length !== 1)
      throw Error("Approved rescue did not write atomically");
    await open();
    await page.getByRole("checkbox").focus();
    await page.keyboard.press("Space");
    await page.getByRole("button", { name: "Continue", exact: true }).click();
    await page
      .getByRole("heading", { name: "Rescue recorded", exact: true })
      .waitFor({ timeout: 20000 });
    if (tasks().length !== 1) throw Error("Repeat approval created duplicates");
    const evidence = {
      date: "2026-10-16",
      org: "agOrg",
      cancelledWithoutChanges: true,
      approvedEscalation: true,
      followUpTasks: 1,
      repeatedApprovalTasks: 1,
      fixture:
        "Disposable synthetic browser test; approval was simulated by automation."
    };
    fs.writeFileSync(
      "docs/approval-ui-verification.json",
      JSON.stringify(evidence, null, 2) + "\n"
    );
    console.log(JSON.stringify(evidence));
  } catch (e) {
    if (page) {
      console.log((await page.locator("body").innerText()).slice(0, 3000));
      await page.screenshot({ path: "/tmp/casepulse-approval-debug.png" });
    }
    throw e;
  } finally {
    if (browser) await browser.close();
    if (caseId) {
      for (const task of query(`SELECT Id FROM Task WHERE WhatId='${caseId}'`))
        invoke([
          "data",
          "delete",
          "record",
          "--sobject",
          "Task",
          "--record-id",
          task.Id,
          ...common
        ]);
      invoke([
        "data",
        "delete",
        "record",
        "--sobject",
        "Case",
        "--record-id",
        caseId,
        ...common
      ]);
    }
  }
})().catch((e) => {
  console.error(
    "Approval UI verification failed:",
    String(e.message).replace(/https?:\/\/[^\s)]+/g, "[URL]")
  );
  process.exitCode = 1;
});
