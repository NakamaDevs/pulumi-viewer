// Layout options of this viewer, like the Aspire dashboard settings. Kept in localStorage
// (every access in try/catch: private windows and blocked storage must still work).
const KEY = "pv:prefs"
const DEFAULTS = {view: "table", orientation: "beside", density: "compact"}

export function readPrefs() {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || "{}")
    return {...DEFAULTS, ...(saved && typeof saved === "object" ? saved : {})}
  } catch (_e) {
    return {...DEFAULTS}
  }
}

function writePrefs(prefs) {
  try { localStorage.setItem(KEY, JSON.stringify(prefs)) } catch (_e) { /* not kept */ }
}

export function applyPrefs(prefs) {
  document.documentElement.dataset.density = prefs.density
}

function syncPressed(el, prefs) {
  el.querySelectorAll("[data-pref]").forEach(b =>
    b.setAttribute("aria-pressed", String(prefs[b.dataset.pref] === b.dataset.value)))
  const theme = (() => { try { return localStorage.getItem("phx:theme") || "system" } catch (_e) { return "system" } })()
  el.querySelectorAll("[data-phx-theme]").forEach(b =>
    b.setAttribute("aria-pressed", String(b.dataset.phxTheme === theme)))
}

export const Settings = {
  mounted() {
    this.prefs = readPrefs()
    syncPressed(this.el, this.prefs)
    this.el.addEventListener("click", e => {
      const pref = e.target.closest("[data-pref]")
      if (pref) {
        this.prefs = {...this.prefs, [pref.dataset.pref]: pref.dataset.value}
        writePrefs(this.prefs)
        applyPrefs(this.prefs)
        this.pushEvent("prefs", this.prefs)
      }
      // theme buttons run first through phx:set-theme; update the pressed state after
      setTimeout(() => syncPressed(this.el, this.prefs), 0)
    })
  },
  updated() { syncPressed(this.el, this.prefs) },
}

// Drag handle of the details panel. The size is kept per orientation.
export const Splitter = {
  mounted() {
    const split = document.getElementById("split")
    const key = () => `pv:split:${split.dataset.orientation}`
    const restore = () => {
      try {
        const v = localStorage.getItem(key())
        if (v) split.style.setProperty("--pv-split", v + "px")
        else split.style.removeProperty("--pv-split")
      } catch (_e) { /* default size */ }
    }
    restore()
    this.restore = restore
    this.el.addEventListener("pointerdown", e => {
      e.preventDefault()
      this.el.setPointerCapture(e.pointerId)
      this.el.classList.add("dragging")
      const beside = split.dataset.orientation === "beside"
      const rect = split.getBoundingClientRect()
      const move = ev => {
        const size = beside ? rect.right - ev.clientX : rect.bottom - ev.clientY
        const max = (beside ? rect.width : rect.height) - 160
        this.size = Math.round(Math.max(200, Math.min(max, size)))
        split.style.setProperty("--pv-split", this.size + "px")
      }
      const up = () => {
        this.el.classList.remove("dragging")
        this.el.removeEventListener("pointermove", move)
        this.el.removeEventListener("pointerup", up)
        if (this.size) { try { localStorage.setItem(key(), String(this.size)) } catch (_e) { /* not kept */ } }
      }
      this.el.addEventListener("pointermove", move)
      this.el.addEventListener("pointerup", up)
    })
    // keyboard: arrows resize by 24px
    this.el.addEventListener("keydown", e => {
      const beside = split.dataset.orientation === "beside"
      const grow = beside ? e.key === "ArrowLeft" : e.key === "ArrowUp"
      const shrink = beside ? e.key === "ArrowRight" : e.key === "ArrowDown"
      if (!grow && !shrink) return
      e.preventDefault()
      const cur = document.getElementById("details").getBoundingClientRect()[beside ? "width" : "height"]
      this.size = Math.round(Math.max(200, cur + (grow ? 24 : -24)))
      split.style.setProperty("--pv-split", this.size + "px")
      try { localStorage.setItem(key(), String(this.size)) } catch (_e) { /* not kept */ }
    })
  },
  updated() { this.restore() },
}
