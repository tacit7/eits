import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { WebglAddon } from "@xterm/addon-webgl"
import "@xterm/xterm/css/xterm.css"

// xterm.js color themes — keyed by DaisyUI data-theme value.
// Dracula: official dracula/visual-studio-code theme terminal colors
// Tokyo Night: official enkia/tokyo-night-vscode-theme terminal colors
// Dark/Light/Autumn: VSCode default Dark+/Light+ ANSI palette
const THEMES = {
  // VSCode Dark+ default terminal colors
  dark: {
    background:          "#1e1e1e",
    foreground:          "#cccccc",
    cursor:              "#cccccc",
    cursorAccent:        "#1e1e1e",
    selectionBackground: "#264f78",
    black:               "#000000",
    brightBlack:         "#666666",
    red:                 "#cd3131",
    brightRed:           "#f14c4c",
    green:               "#0dbc79",
    brightGreen:         "#23d18b",
    yellow:              "#e5e510",
    brightYellow:        "#f5f543",
    blue:                "#2472c8",
    brightBlue:          "#3b8eea",
    magenta:             "#bc3fbc",
    brightMagenta:       "#d670d6",
    cyan:                "#11a8cd",
    brightCyan:          "#29b8db",
    white:               "#e5e5e5",
    brightWhite:         "#e5e5e5",
  },

  // VSCode Light+ default terminal colors
  light: {
    background:          "#ffffff",
    foreground:          "#000000",
    cursor:              "#000000",
    cursorAccent:        "#ffffff",
    selectionBackground: "#add6ff",
    black:               "#000000",
    brightBlack:         "#666666",
    red:                 "#cd3131",
    brightRed:           "#cd3131",
    green:               "#00bc00",
    brightGreen:         "#14ce14",
    yellow:              "#949800",
    brightYellow:        "#b5ba00",
    blue:                "#0451a5",
    brightBlue:          "#0451a5",
    magenta:             "#bc05bc",
    brightMagenta:       "#bc05bc",
    cyan:                "#0598bc",
    brightCyan:          "#0598bc",
    white:               "#555555",
    brightWhite:         "#a5a5a5",
  },

  // Official Dracula VSCode theme — dracula/visual-studio-code
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
    blue:                "#bd93f9",
    brightBlue:          "#d6acff",
    magenta:             "#ff79c6",
    brightMagenta:       "#ff92df",
    cyan:                "#8be9fd",
    brightCyan:          "#a4ffff",
    white:               "#f8f8f2",
    brightWhite:         "#ffffff",
  },

  // Official Tokyo Night VSCode theme — enkia/tokyo-night-vscode-theme
  tokyonight: {
    background:          "#16161e",
    foreground:          "#787c99",
    cursor:              "#c0caf5",
    cursorAccent:        "#16161e",
    selectionBackground: "#515c7e4d",
    black:               "#363b54",
    brightBlack:         "#363b54",
    red:                 "#f7768e",
    brightRed:           "#f7768e",
    green:               "#73daca",
    brightGreen:         "#73daca",
    yellow:              "#e0af68",
    brightYellow:        "#e0af68",
    blue:                "#7aa2f7",
    brightBlue:          "#7aa2f7",
    magenta:             "#bb9af7",
    brightMagenta:       "#bb9af7",
    cyan:                "#7dcfff",
    brightCyan:          "#7dcfff",
    white:               "#787c99",
    brightWhite:         "#acb0d0",
  },

  // Autumn — no canonical VSCode theme; using EITS palette
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
