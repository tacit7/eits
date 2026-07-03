export const DragUpload = {
  mounted() {
    this._overlay = this.el.querySelector('#drag-overlay')
    this._active = false

    // Window-level listeners: more reliable for detecting when drag
    // enters/leaves the browser window vs element-boundary noise.
    this._onDragEnter = (e) => {
      const types = e.dataTransfer?.types
      if (!types) return
      if (!Array.from(types).includes('Files')) return
      if (!this._active) {
        this._active = true
        this._overlay?.classList.remove('hidden')
      }
    }

    this._onDragLeave = (e) => {
      // relatedTarget is null only when the cursor leaves the browser window
      if (e.relatedTarget === null) {
        this._active = false
        this._overlay?.classList.add('hidden')
      }
    }

    this._onDrop = () => {
      this._active = false
      this._overlay?.classList.add('hidden')
    }

    // Tauri native drag events (WKWebView doesn't fire HTML5 drag events for
    // files dragged from Finder — only these custom events from the Rust side).
    this._onTauriDragEnter = () => {
      if (!this._active) {
        this._active = true
        this._overlay?.classList.remove('hidden')
      }
    }

    this._onTauriDragLeave = () => {
      this._active = false
      this._overlay?.classList.add('hidden')
    }

    this._onTauriDrop = (e) => {
      this._active = false
      this._overlay?.classList.add('hidden')
      // Forward the dropped file paths to the DM LiveView. Must go through a
      // hook: this.pushEvent is the only public API for pushing to the view
      // (the old app.js relay used the nonexistent view.pushEvent and dropped
      // every native file drop silently).
      const paths = e.detail?.paths ?? []
      if (paths.length) {
        this.pushEvent('tauri_file_drop', { paths })
      }
    }

    window.addEventListener('dragenter', this._onDragEnter)
    window.addEventListener('dragleave', this._onDragLeave)
    window.addEventListener('drop', this._onDrop)
    window.addEventListener('tauri:file-drag-enter', this._onTauriDragEnter)
    window.addEventListener('tauri:file-drag-leave', this._onTauriDragLeave)
    window.addEventListener('tauri:file-drop', this._onTauriDrop)
  },
  destroyed() {
    window.removeEventListener('dragenter', this._onDragEnter)
    window.removeEventListener('dragleave', this._onDragLeave)
    window.removeEventListener('drop', this._onDrop)
    window.removeEventListener('tauri:file-drag-enter', this._onTauriDragEnter)
    window.removeEventListener('tauri:file-drag-leave', this._onTauriDragLeave)
    window.removeEventListener('tauri:file-drop', this._onTauriDrop)
  }
}
