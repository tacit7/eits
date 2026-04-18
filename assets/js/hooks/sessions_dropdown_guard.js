/**
 * SessionsDropdownGuard
 *
 * Prevents DaisyUI dropdowns from closing when LiveView patches a stream
 * item (e.g., a PATCH /sessions/:uuid triggers stream_insert which replaces
 * the DOM row containing the open dropdown).
 *
 * Attaches to the phx-update="stream" container. beforeUpdate captures which
 * stream item has an open dropdown; updated re-focuses the trigger button so
 * the dropdown re-opens after the DOM replacement.
 */
export const SessionsDropdownGuard = {
  beforeUpdate() {
    this._openItemId = null;

    // A DaisyUI dropdown stays open while any of its children have focus.
    // The tabindex="0" button on the summary element is what holds focus.
    const focused = this.el.querySelector(":focus");
    if (!focused) return;

    // Walk up to the nearest stream item (id starts with "si-")
    const item = focused.closest("[id]");
    if (item && item !== this.el) {
      this._openItemId = item.id;
    }
  },

  updated() {
    if (!this._openItemId) return;

    const item = document.getElementById(this._openItemId);
    if (!item) return;

    // Re-focus the dropdown toggle button so :focus-within reopens the menu.
    const btn = item.querySelector(".dropdown [tabindex='0']");
    if (btn) btn.focus();

    this._openItemId = null;
  },
};
