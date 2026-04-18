/**
 * SessionsDropdownGuard
 *
 * Prevents DaisyUI dropdowns from closing when LiveView patches a stream
 * item (e.g., a PATCH /sessions/:uuid triggers stream_insert which replaces
 * the DOM row containing the open dropdown).
 *
 * Why beforeUpdate/updated don't work here:
 * Those hook callbacks fire when the *element the hook is attached to* gets
 * a diff from the server. A phx-update="stream" container's attributes don't
 * change when children are inserted — so those callbacks never fire.
 *
 * Correct approach:
 * 1. Track which stream item has focus via focusin/focusout listeners.
 * 2. On focusout, check e.target.isConnected — if the element was removed
 *    by a LiveView patch it will be disconnected, so we keep the item ID.
 *    If the user deliberately blurred, the element is still connected, so
 *    we clear the ID.
 * 3. A MutationObserver on the container fires (as a microtask) after the
 *    DOM batch completes. At that point the new element is in the DOM and
 *    we re-focus its dropdown button, restoring :focus-within.
 */
export const SessionsDropdownGuard = {
  mounted() {
    this._focusedItemId = null;

    this._onFocusIn = (e) => {
      const item = e.target.closest("[id^='si-']");
      this._focusedItemId = item?.id ?? null;
    };

    this._onFocusOut = (e) => {
      // If the element is still in the DOM, the user deliberately blurred — clear state.
      // If it was disconnected (removed by a LiveView stream patch), keep the ID so
      // the MutationObserver can refocus the replacement element.
      if (e.target.isConnected) {
        this._focusedItemId = null;
      }
    };

    this.el.addEventListener("focusin", this._onFocusIn);
    this.el.addEventListener("focusout", this._onFocusOut);

    this._observer = new MutationObserver(() => {
      if (!this._focusedItemId) return;

      const item = document.getElementById(this._focusedItemId);
      this._focusedItemId = null;

      if (!item || item.contains(document.activeElement)) return;

      const btn = item.querySelector(".dropdown [tabindex='0']");
      if (btn) btn.focus();
    });

    // childList only — we only care about rows being added/removed, not attribute changes.
    this._observer.observe(this.el, { childList: true });
  },

  destroyed() {
    this._observer?.disconnect();
    this.el.removeEventListener("focusin", this._onFocusIn);
    this.el.removeEventListener("focusout", this._onFocusOut);
  },
};
