// FileAttach hook: reads a file input and appends its content to the description textarea.
// Usage: <input type="file" phx-hook="FileAttach" data-target="desc-textarea-id" />
export const FileAttach = {
  mounted() {
    this.el.addEventListener("change", (e) => {
      const file = e.target.files[0]
      if (!file) return

      const targetId = this.el.dataset.target
      const textarea = targetId ? document.getElementById(targetId) : null
      if (!textarea) return

      const reader = new FileReader()
      reader.onload = (ev) => {
        const content = ev.target.result
        const filename = file.name
        const separator = textarea.value.trim() ? "\n\n" : ""
        textarea.value += `${separator}--- ${filename} ---\n${content}`
        // Dispatch input event so LiveView phx-update="ignore" doesnt matter
        textarea.dispatchEvent(new Event("input", {bubbles: true}))
        // Reset so same file can be re-attached
        this.el.value = ""
      }
      reader.readAsText(file)
    })
  }
}
