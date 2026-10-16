// Native HXL Playground previews from deployed Apex output; not a live Claude session.
const { chromium } = require("playwright");
const fs = require("node:fs");
const composition = JSON.parse(
  fs.readFileSync(
    "force-app/main/default/uiWidgets/casePulseConsole/casePulseConsole.json",
    "utf8"
  )
).contentBody.widgetBody;
(async () => {
  const entries = ["team", "my"].map((view) => {
    const data = JSON.parse(
      fs.readFileSync(`docs/fixtures/${view}.json`, "utf8")
    );
    const fragment = structuredClone(composition);
    fragment.dataProviders = [
      {
        definition: "inline-data",
        expressionKey: "$attrs",
        inline: true,
        value: data.$attrs
      }
    ];
    return {
      id: `casepulse-${view}`,
      name: `CasePulse ${view === "team" ? "Manager" : "Rep Layout"} · Playground Preview`,
      label: `CasePulse ${view === "team" ? "Manager" : "Rep Layout"} · Playground Preview`,
      icon: "headset",
      categoryId: "local",
      fragment,
      savedAt: new Date().toISOString()
    };
  });
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const page = await browser.newPage({
      viewport: { width: 1720, height: 1250 },
      deviceScaleFactor: 1
    });
    await page.addInitScript(
      (entries) =>
        localStorage.setItem("uem-mosaic-fragments", JSON.stringify(entries)),
      entries
    );
    for (const [view, file] of [
      ["team", "manager-console-preview"],
      ["my", "rep-queue-preview"]
    ]) {
      await page.goto(
        `https://www.headlessexperiencelayer.com/#widget/local/casepulse-${view}`,
        { waitUntil: "domcontentloaded" }
      );
      await page
        .getByRole("button", { name: "Claude", exact: true })
        .last()
        .click();
      await page.waitForTimeout(2500);
      const body = (
        await Promise.all(
          page.frames().map((frame) =>
            frame
              .locator("body")
              .innerText()
              .catch(() => "")
          )
        )
      ).join("\n");
      if (!body.includes("[DEMO]") || body.includes("Error evaluating"))
        throw Error("Widget failed to render");
      await page.screenshot({
        path: `docs/screenshots/${file}.png`,
        clip: { x: 240, y: 55, width: 995, height: 1100 }
      });
      console.log(
        `Captured ${file}: native Claude preview using ${view} Apex snapshot.`
      );
    }
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
