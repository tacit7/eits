export const CanvasTabHook = {
  mounted() {
    this.el.addEventListener("dblclick", () => {
      this.pushEvent("start_rename", {"canvas-id": this.el.dataset.canvasId})
    })
  }
}
