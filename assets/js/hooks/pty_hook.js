import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import "@xterm/xterm/css/xterm.css"

export const PtyHook = {
  mounted() {
    const term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
      theme: {
        background: "#09090b",   // zinc-950
        foreground: "#e4e4e7",   // zinc-200
        cursor:     "#a1a1aa",   // zinc-400
        black:      "#18181b",
        brightBlack: "#3f3f46",
        red:        "#f87171",
        brightRed:  "#fca5a5",
        green:      "#4ade80",
        brightGreen:"#86efac",
        yellow:     "#facc15",
        brightYellow:"#fde047",
        blue:       "#60a5fa",
        brightBlue: "#93c5fd",
        magenta:    "#c084fc",
        brightMagenta:"#d8b4fe",
        cyan:       "#22d3ee",
        brightCyan: "#67e8f9",
        white:      "#d4d4d8",
        brightWhite:"#f4f4f5",
      },
      scrollback: 5000,
      allowProposedApi: true,
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.loadAddon(new WebLinksAddon())
    term.open(this.el)
    fitAddon.fit()

    // Send input to server
    term.onData(data => {
      this.pushEvent("pty_input", { data })
    })

    // Notify server of resize
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
