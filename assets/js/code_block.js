// Read-only code panel rendered with @pierre/diffs (https://diffs.com), mounted as a LiveView hook.
// <div phx-hook="CodeBlock" phx-update="ignore" data-name="outputs.json" data-code="..."></div>
import {File} from "@pierre/diffs"

const themeType = () => {
  const t = document.documentElement.dataset.theme
  return t === "light" || t === "dark" ? t : "system"
}

export const CodeBlock = {
  mounted() {
    this.el.replaceChildren() // drop the no-JS <pre> fallback
    this.view = new File({themeType: themeType(), overflow: "wrap", disableFileHeader: true})
    this.render()
    // follow the daisyUI theme toggle
    this.observer = new MutationObserver(() => this.view.setThemeType(themeType()))
    this.observer.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
  },
  updated() { this.render() },
  destroyed() {
    this.observer.disconnect()
    this.view.cleanUp()
  },
  render() {
    this.view.render({
      file: {name: this.el.dataset.name, contents: this.el.dataset.code || ""},
      containerWrapper: this.el,
    })
  },
}
