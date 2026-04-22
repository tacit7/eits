/**
 * SessionsDropdownGuard
 *
 * Prevents <details> dropdowns from closing when LiveView stream_insert
 * replaces a stream item row (remove old DOM node, insert new one).
 *
 * phx-update="ignore" on the <details> itself does NOT help here — it only
 * prevents morphdom from patching the element during a diff. When the parent
 * stream item is removed and reinserted wholesale, the <details> is a brand
 * new element with no open state.
 *
 * How this works:
 * 1. A capture-phase "toggle" listener tracks which <details> is currently
 *    open by ID. Capture phase ensures it fires before children handle it.
 * 2. A MutationObserver on the stream container fires after each stream
 *    mutation (direct childList only — rows are direct children).
 * 3. On mutation: if _openDetailsId is still set, the user did not close the
 *    dropdown — the DOM swap did. Find the new element by ID and set open=true.
 */
export const SessionsDropdownGuard = {
  mounted() {
    this._openDetailsId = null;

    // Capture phase: fires before any bubbling listeners on children.
    this._onToggle = (e) => {
      const details = e.target.closest("details");
      if (!details) return;
      if (details.open) {
        this._openDetailsId = details.id;
      } else if (this._openDetailsId === details.id) {
        this._openDetailsId = null;
      }
    };

    this.el.addEventListener("toggle", this._onToggle, true);

    this._observer = new MutationObserver(() => {
      if (!this._openDetailsId) return;
      const details = document.getElementById(this._openDetailsId);
      if (details && !details.open) details.open = true;
    });

    // childList only — stream inserts/removes are direct children of this el.
    this._observer.observe(this.el, { childList: true });
  },

  destroyed() {
    this._observer?.disconnect();
    this.el.removeEventListener("toggle", this._onToggle, true);
  },
};
