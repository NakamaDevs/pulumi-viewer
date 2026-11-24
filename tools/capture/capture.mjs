// Takes the README screenshots and the demo video. Run against a server with the demo state:
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

// Stacks
await page.goto(BASE + "/")
await expect(page.getByText("webapp", {exact: true})).toBeVisible()
await expect(page.getByText("platform", {exact: true})).toBeVisible()
await pause(1200); await shot("stacks")

// Graph
await page.getByRole("link", {name: /^dev/}).click()
await expect(page.locator(".react-flow__node")).toHaveCount(23, {timeout: 10000})
await pause(1500); await shot("graph")

// Resource details from the graph
await page.locator(".react-flow__node", {hasText: "postgres"}).first().click()
await expect(page.getByText("[secret]").first()).toBeVisible()
await pause(1500); await shot("details")

// Providers toggle
await page.getByText("Show providers").click()
await expect(page.locator(".react-flow__node")).toHaveCount(24)
await pause(1200)
await page.getByText("Show providers").click()

// Resources table + filter
await page.getByRole("tab", {name: /Resources/}).click()
await page.getByPlaceholder("Filter by name, type or id").pressSequentially("ecs", {delay: 120})
await expect(page.locator("tbody tr")).toHaveCount(5)
await pause(1200); await shot("resources")

// History
await page.getByRole("tab", {name: "History"}).click()
await expect(page.getByText("Bump postgres to 17")).toBeVisible()
await pause(1500); await shot("history")

// Light theme
await page.evaluate(() => document.documentElement.setAttribute("data-theme", "light"))
await page.getByRole("tab", {name: "Graph"}).click()
await expect(page.locator(".react-flow__node")).toHaveCount(23)
await pause(1500); await shot("graph-light")

await ctx.close(); await browser.close()
const [video] = readdirSync(RAW).filter(f => f.endsWith(".webm"))
renameSync(RAW + video, OUT + "demo.webm"); rmSync(RAW, {recursive: true})
console.log("screenshots and demo.webm in", OUT)
