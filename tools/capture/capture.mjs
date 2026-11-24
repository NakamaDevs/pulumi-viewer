// Takes the README screenshots and the demo video, with assertions on each step.
// Run against a server with the demo state:
//   docker run --rm -p 4078:4000 pulumi-viewer   then   BASE_URL=http://localhost:4078 node capture.mjs
import {chromium, expect} from "playwright/test"
import {mkdirSync, readdirSync, renameSync, rmSync} from "node:fs"

const BASE = process.env.BASE_URL || "http://localhost:4000"
const OUT = new URL("../../docs/media/", import.meta.url).pathname
const RAW = OUT + "raw/"
mkdirSync(RAW, {recursive: true})

const browser = await chromium.launch()
const ctx = await browser.newContext({
  viewport: {width: 1280, height: 760}, deviceScaleFactor: 2, colorScheme: "dark",
  recordVideo: {dir: RAW, size: {width: 1280, height: 760}},
})
const page = await ctx.newPage()
const shot = name => page.screenshot({path: OUT + name + ".png"})
const pause = ms => page.waitForTimeout(ms)
const setting = async (pref, value) => {
  await page.locator("#settings-open").click()
  await expect(page.locator("#settings-dialog")).toBeVisible()
  await page.locator(`#settings-dialog [data-pref="${pref}"][data-value="${value}"]`).click()
  await expect(page.locator(`#settings-dialog [data-pref="${pref}"][data-value="${value}"]`)).toHaveAttribute("aria-pressed", "true")
  await pause(500)
  await page.keyboard.press("Escape")
  await expect(page.locator("#settings-dialog")).toBeHidden()
}

// Shell: top bar with tabs, sources menu, help and settings
await page.goto(BASE + "/")
await expect(page.locator("header nav a[aria-current=page]")).toHaveText(/Stacks/)
await expect(page.locator("header nav a")).toHaveText([/Stacks/, /Resources/, /History/])
await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")

// Stacks: tree list grouped by environment
await expect(page.locator("#group-dev [data-row=stack]")).toHaveCount(1)
await expect(page.locator("[data-row=stack]")).toHaveCount(3)
await pause(1200); await shot("stacks")

// Stack page: table first, then the graph through the Table / Graph toggle
await page.locator("#group-dev [data-row=stack] a").click()
await expect(page.locator("#resource-list [data-urn]")).toHaveCount(24)
await page.locator('button[phx-value-tab="graph"]').click()
await expect(page.locator(".react-flow__node")).toHaveCount(23, {timeout: 10000})
await pause(1500); await shot("graph")

// Resource details beside the graph
await page.locator(".react-flow__node", {hasText: "postgres"}).first().click()
await expect(page.locator("#details[data-orientation=beside]")).toBeVisible()
await expect(page.getByText("[secret]").first()).toBeVisible()
await pause(1500); await shot("details")
await page.locator("#details button[phx-click=close]").click()
await expect(page.locator("#details")).toHaveCount(0)

// Providers toggle
await page.getByText("Show providers").click()
await expect(page.locator(".react-flow__node")).toHaveCount(24)
await pause(800)
await page.getByText("Show providers").click()

// Resources table: filter, parent/child rows, details below (orientation option)
await page.locator('button[phx-value-tab="resources"]').click()
await page.getByPlaceholder("Filter by name, type or id").pressSequentially("ecs", {delay: 120})
await expect(page.locator("#resource-list [data-urn][data-depth='1']")).toHaveCount(5)
await setting("orientation", "below")
await page.locator("#resource-list [data-urn]", {hasText: "worker"}).first().click()
await expect(page.locator("#details[data-orientation=below]")).toBeVisible()
await pause(1200); await shot("resources")
await setting("orientation", "beside")
await expect(page.locator("#details[data-orientation=beside]")).toBeVisible()

// All resources across stacks
await page.locator("header nav a", {hasText: "Resources"}).click()
await expect(page.locator("[data-stack-group]")).toHaveCount(3)
await pause(1000); await shot("all-resources")

// History across stacks, with details
await page.locator("header nav a", {hasText: "History"}).click()
await expect(page.getByText("Bump postgres to 17").first()).toBeVisible()
await page.locator("#history tr[data-update]", {hasText: "Bump postgres to 17"}).first().click()
await expect(page.locator("#details [data-section=update]")).toBeVisible()
await pause(1500); await shot("history")

// Settings sheet
await page.locator("#settings-open").click()
await expect(page.locator("#settings-dialog")).toBeVisible()
await pause(1000); await shot("settings")
await page.keyboard.press("Escape")

// Light theme from the settings, graph again
await page.locator("#settings-open").click()
await page.locator('#settings-dialog [data-phx-theme="light"]').click()
await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
await page.keyboard.press("Escape")
await page.goto(BASE + "/sources/default/stacks/webapp/dev")
await page.locator('button[phx-value-tab="graph"]').click()
await expect(page.locator(".react-flow__node")).toHaveCount(23)
await pause(1500); await shot("graph-light")
await page.goto(BASE + "/")
await pause(1000); await shot("stacks-light")

await ctx.close(); await browser.close()
const [video] = readdirSync(RAW).filter(f => f.endsWith(".webm"))
renameSync(RAW + video, OUT + "demo.webm"); rmSync(RAW, {recursive: true})
console.log("screenshots and demo.webm in", OUT)
