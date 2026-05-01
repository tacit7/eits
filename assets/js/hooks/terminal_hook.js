/**
 * TerminalHook — xterm.js hook for canvas terminal windows.
 *
 * Identical to PtyHook but scopes push/handle events to the terminal's ID so
 * multiple terminals on the same canvas page can coexist without interference.
 *
 * Events pushed to server:  "pty_input", "pty_resize"  (same as TerminalLive)
 * Events received from server: "pty_output_<id>"       (scoped by terminal ID)
 *
 * The container element must carry data-terminal-id=<id>.
 */

import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import "@xterm/xterm/css/xterm.css"

export const TerminalHook = {
  mounted() {
    const terminalId = this.el.dataset.terminalId

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
      theme: {
        background: "#09090b",    // zinc-950
        foreground: "#e4e4e7",    // zinc-200
        cursor:     "#a1a1aa",    // zinc-400
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

    // Send input to server (same event name as TerminalLive — routed by phx-target)
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

    // Receive output — scoped event name prevents cross-terminal interference
    this.handleEvent(`pty_output_${terminalId}`, ({ data }) => {
      term.write(Uint8Array.from(atob(data), c => c.charCodeAt(0)))
    })

    this._term = term
    this._fitAddon = fitAddon

    term.focus()
  },

  destroyed() {
    this._resizeObserver?.disconnect()
    this._term?.dispose()
  }
}
