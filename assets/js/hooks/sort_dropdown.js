/**
 * SortDropdown hook
 *
 * Syncs the visible sort label inside a phx-update="ignore" <details> dropdown.
 *
 * Why MutationObserver instead of updated():
 *   LiveView's updated() callback never fires on phx-update="ignore" elements —
 *   LiveView skips morphdom patching for the entire ignored subtree, so the hook
 *   lifecycle callback is never called. However, LiveView DOES sync data-*
 *   attributes on ignored elements. MutationObserver detects those data-label
 *   changes independently of the hook lifecycle.
 *
 * Why phx-update="ignore" at all:
 *   Without it, any background LiveView re-render (PubSub task/session events)
 *   morphs the <details> element back to its server-rendered state (no `open`
 *   attribute), forcibly closing the dropdown mid-interaction before the user
 *   can click an option.
 *
 * Usage:
 *   <details id="stable-id" phx-update="ignore" phx-hook="SortDropdown"
 *            data-label={@computed_label} class="dropdown">
 *     <summary>Sort: <span class="js-sort-label">{@computed_label}</span> ...</summary>
 *     <ul>...</ul>
 *   </details>
 */
const SortDropdown = {
  mounted() {
    this._sync()
    this._observer = new MutationObserver(() => this._sync())
    this._observer.observe(this.el, {
      attributes: true,
      attributeFilter: ["data-label"],
    })
  },

  _sync() {
    const label = this.el.dataset.label
    const span = this.el.querySelector(".js-sort-label")
    if (span && label !== undefined) span.textContent = label
  },

  destroyed() {
    this._observer?.disconnect()
  },
}

export default SortDropdown
