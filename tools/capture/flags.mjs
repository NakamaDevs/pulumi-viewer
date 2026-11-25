// Evidence for resource options and safety checks (ENG-9422), with assertions.
// Run against two servers with the fixture test/fixtures/guarded:
//   before (main):  PULUMI_VIEWER_SOURCES=guarded=file://<fixture> PORT=4091 mix phx.server
//   after (branch): the same plus PULUMI_VIEWER_INVENTORY=<fixture>/inventory, PORT=4092
//   BEFORE_URL=http://localhost:4091 AFTER_URL=http://localhost:4092 OUT=<dir> node flags.mjs
// BEFORE_URL is optional: without it only the after screenshots are taken.
import {chromium, expect} from "playwright/test"
import {mkdirSync} from "node:fs"

const OUT = process.env.OUT || new URL("../../docs/media/flags/", import.meta.url).pathname
mkdirSync(OUT, {recursive: true})
const browser = await chromium.launch()
const ctx = await browser.newContext({viewport: {width: 1280, height: 640}, deviceScaleFactor: 2, colorScheme: "dark"})
const page = await ctx.newPage()
const shot = (name, el) => (el ? page.locator(el) : page).screenshot({path: OUT + name + ".png"})
const logs = "[data-urn$='::logs']"

if (process.env.BEFORE_URL) {
  await page.goto(process.env.BEFORE_URL + "/resources")
  await expect(page.locator(logs)).toBeVisible()
  await page.locator(logs).click()
  await expect(page.getByText("Protected")).toBeVisible()
  await page.waitForTimeout(500); await shot("before-resources")
  await page.goto(process.env.BEFORE_URL + "/history")
  await expect(page.locator("#history-table tbody tr, table tbody tr").first()).toBeVisible()
  await page.waitForTimeout(500); await shot("before-history")
}

const AFTER = process.env.AFTER_URL || "http://localhost:4092"
await page.goto(AFTER + "/resources")
await expect(page.locator(`${logs} [data-kind=cloudformation]`)).toHaveText("CFN")
await expect(page.locator(`${logs} [data-finding][data-sev=error]`)).toBeVisible()
await expect(page.locator("[data-urn$='::assets'] [data-flag=retain]")).toBeVisible()
await expect(page.locator("#findings-error")).toHaveText(/2 errors/)
await page.locator(logs).click()
await expect(page.locator("[data-check=option_mismatch]")).toContainText("retainOnDelete")
await page.waitForTimeout(500); await shot("after-resources")

await page.locator("select[name=flag]").selectOption("no-retain")
await expect(page.locator("[data-urn$='::assets']")).toHaveCount(0)
await expect(page.locator(logs)).toBeVisible()
await page.waitForTimeout(500); await shot("after-filter-no-retain")

await page.goto(AFTER + "/history")
const edit = page.locator("tr[data-result='state edit']")
await expect(edit).toBeVisible()
await edit.click()
await expect(page.locator("span.pv-chip[data-op='protect off']")).toBeVisible()
await page.waitForTimeout(500); await shot("after-history-state-edit")

await browser.close()
console.log("ok", OUT)
