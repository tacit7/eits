import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { WebglAddon } from "@xterm/addon-webgl"
import "@xterm/xterm/css/xterm.css"

// xterm.js color themes — keyed by DaisyUI data-theme value.
// Colors sourced from ~/.claude/themes/*.json (EITS canonical palette).
const THEMES = {
  dark: {
    background:          "#0f172a",
    foreground:          "#e2e8f0",
    cursor:              "#e2e8f0",
    cursorAccent:        "#0f172a",
    selectionBackground: "#1e3a5f",
    black:               "#1e293b",
    brightBlack:         "#334155",
    red:                 "#f87171",
    brightRed:           "#fca5a5",
    green:               "#4ade80",
    brightGreen:         "#86efac",
    yellow:              "#fbbf24",
    brightYellow:        "#fde68a",
    blue:                "#60a5fa",
    brightBlue:          "#93c5fd",
    magenta:             "#a78bfa",
    brightMagenta:       "#c4b5fd",
    cyan:                "#22d3ee",
    brightCyan:          "#67e8f9",
    white:               "#94a3b8",
    brightWhite:         "#e2e8f0",
  },

  light: {
    background:          "#ffffff",
    foreground:          "#1e293b",
    cursor:              "#1e293b",
    cursorAccent:        "#ffffff",
    selectionBackground: "#bfdbfe",
    black:               "#f1f5f9",
    brightBlack:         "#94a3b8",
    red:                 "#dc2626",
    brightRed:           "#ef4444",
    green:               "#16a34a",
    brightGreen:         "#22c55e",
    yellow:              "#d97706",
    brightYellow:        "#f59e0b",
    blue:                "#2563eb",
    brightBlue:          "#3b82f6",
    magenta:             "#7c3aed",
    brightMagenta:       "#8b5cf6",
    cyan:                "#0891b2",
    brightCyan:          "#06b6d4",
    white:               "#475569",
    brightWhite:         "#1e293b",
  },

  dracula: {
    background:          "#282a36",
    foreground:          "#f8f8f2",
    cursor:              "#f8f8f2",
    cursorAccent:        "#282a36",
    selectionBackground: "#44475a",
    black:               "#21222c",
    brightBlack:         "#6272a4",
    red:                 "#ff5555",
    brightRed:           "#ff6e6e",
    green:               "#50fa7b",
    brightGreen:         "#69ff94",
    yellow:              "#f1fa8c",
    brightYellow:        "#ffffa5",
    blue:                "#8be9fd",
    brightBlue:          "#a4ffff",
    magenta:             "#bd93f9",
    brightMagenta:       "#ff79c6",
    cyan:                "#8be9fd",
    brightCyan:          "#a4ffff",
    white:               "#f8f8f2",
    brightWhite:         "#ffffff",
  },

  autumn: {
    background:          "#1c1208",
    foreground:          "#fef3c7",
    cursor:              "#fef3c7",
    cursorAccent:        "#1c1208",
    selectionBackground: "#4a2e10",
    black:               "#292116",
    brightBlack:         "#78350f",
    red:                 "#ef4444",
    brightRed:           "#f87171",
    green:               "#4ade80",
    brightGreen:         "#86efac",
    yellow:              "#fbbf24",
    brightYellow:        "#fde68a",
    blue:                "#60a5fa",
    brightBlue:          "#93c5fd",
    magenta:             "#c084fc",
    brightMagenta:       "#d8b4fe",
    cyan:                "#67e8f9",
    brightCyan:          "#a5f3fc",
    white:               "#92400e",
    brightWhite:         "#fef3c7",
  },
}

function getXtermTheme() {
  const daisyTheme = document.documentElement.getAttribute("data-theme") || "dark"
  return THEMES[daisyTheme] || THEMES.dark
}

export const PtyHook = {
  mounted() {
    const term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
      theme: getXtermTheme(),
      scrollback: 5000,
      allowProposedApi: true,
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.loadAddon(new WebLinksAddon())
    term.open(this.el)

    // Load WebGL renderer for GPU-accelerated painting. Falls back to the
    // default canvas renderer if WebGL2 is unavailable (e.g. headless browser,
    // software renderer). Must be loaded after term.open().
    try {
      const webgl = new WebglAddon()
      webgl.onContextLoss(() => webgl.dispose())
      term.loadAddon(webgl)
    } catch (_) {
      // WebGL unavailable — xterm.js keeps the canvas renderer
    }

    fitAddon.fit()

    // Send initial terminal size to server unconditionally.
    // term.onResize only fires when size CHANGES — if fitAddon.fit() computes
    // the same dimensions as xterm.js's default (e.g. container still at 0 size
    // during the first render), no resize event fires and the auto-launch command
    // is never triggered. Pushing dimensions explicitly here guarantees the server
    // knows the size and can fire the launch command on mount.
    this.pushEvent("pty_resize", { cols: term.cols, rows: term.rows })

    // Send input to server
    term.onData(data => {
      this.pushEvent("pty_input", { data })
    })

    // Notify server of subsequent resize
    term.onResize(({ cols, rows }) => {
      this.pushEvent("pty_resize", { cols, rows })
    })

    // Resize observer keeps terminal filling its container
    this._resizeObserver = new ResizeObserver(() => {
      fitAddon.fit()
    })
    this._resizeObserver.observe(this.el)

    // Receive output from server (base64-encoded to survive JSON)
    this.handleEvent("pty_output", ({ data }) => {
      term.write(Uint8Array.from(atob(data), c => c.charCodeAt(0)))
    })

    // Watch for DaisyUI theme changes and re-apply xterm theme
    this._themeObserver = new MutationObserver(() => {
      term.options.theme = getXtermTheme()
    })
    this._themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    })

    this._term = term
    this._fitAddon = fitAddon

    // Focus on mount
    term.focus()
  },

  destroyed() {
    this._resizeObserver?.disconnect()
    this._themeObserver?.disconnect()
    this._term?.dispose()
  }
}
