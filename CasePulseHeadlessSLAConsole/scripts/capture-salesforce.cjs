// Capture the real deployed confirmation screen. Never log session URLs or cookies.
const { chromium } = require("playwright");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
(async () => {
  const sf = process.cwd() + "/node_modules/.bin/sf";
  const invoke = (args) =>
    JSON.parse(
      execFileSync(sf, args, {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"]
      })
    );
  const q = invoke([
    "data",
    "query",
    "--target-org",
    "agOrg",
    "--query",
    "SELECT Id FROM Case WHERE CasePulse_Demo__c=true AND Subject LIKE '%Acme%' LIMIT 1",
    "--json"
  ]);
  const caseId = q.result.records[0].Id;
  const login = invoke([
    "org",
    "open",
    "--target-org",
    "agOrg",
    "--url-only",
    "--json"
  ]);
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: 1
  });
  await page.goto(login.result.url, {
    waitUntil: "domcontentloaded",
    timeout: 60000
  });
  await page.waitForURL(
    (url) => url.hostname.endsWith(".lightning.force.com"),
    { timeout: 60000 }
  );
  const origin = new URL(login.result.url).origin;
  await page.goto(origin + "/flow/CasePulse_Confirm_Rescue?caseId=" + caseId, {
    waitUntil: "domcontentloaded",
    timeout: 60000
  });
  await page
    .getByRole("heading", { name: "Approve case rescue", exact: true })
    .waitFor({ timeout: 30000 });
  console.log((await page.locator("body").innerText()).slice(0, 6000));
  console.log("BUTTONS", await page.getByRole("button").allTextContents());
  await page.screenshot({
    path: "docs/screenshots/approval.png",
    fullPage: true
  });
  await browser.close();
})().catch(() => {
  console.error("Salesforce UI capture failed. Session details suppressed.");
  process.exitCode = 1;
});
