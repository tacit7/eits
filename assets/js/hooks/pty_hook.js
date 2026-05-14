import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { WebglAddon } from "@xterm/addon-webgl"
import "@xterm/xterm/css/xterm.css"

export const PtyHook = {
  mounted() {
    const term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
      theme: {
        // Tokyo Night
        background:    "#1a1b2e",
        foreground:    "#c0caf5",
        cursor:        "#c0caf5",
        cursorAccent:  "#1a1b2e",
        selectionBackground: "#283457",
        black:         "#15161e",
        brightBlack:   "#414868",
        red:           "#f7768e",
        brightRed:     "#f7768e",
        green:         "#9ece6a",
        brightGreen:   "#9ece6a",
        yellow:        "#e0af68",
        brightYellow:  "#e0af68",
        blue:          "#7aa2f7",
        brightBlue:    "#7aa2f7",
        magenta:       "#bb9af7",
        brightMagenta: "#bb9af7",
        cyan:          "#7dcfff",
        brightCyan:    "#7dcfff",
        white:         "#a9b1d6",
        brightWhite:   "#c0caf5",
      },
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

    this._term = term
    this._fitAddon = fitAddon

    // Focus on mount
    term.focus()
  },

  destroyed() {
    this._resizeObserver?.disconnect()
    this._term?.dispose()
  }
}
