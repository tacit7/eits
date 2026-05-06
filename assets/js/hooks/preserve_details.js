/**
 * PreserveDetails — preserves the open/closed state of a <details> element
 * across LiveView morphdom patches.
 *
 * Without this, when a stream row containing a <details> is patched (e.g. a
 * tool_cluster row gets new events), morphdom reconciles the element against
 * the server-rendered HTML which never includes the `open` attribute. Any
 * cluster the user has expanded collapses unexpectedly on update.
 *
 * Usage: add phx-hook="PreserveDetails" to the <details> element.
 */
export const PreserveDetails = {
  beforeUpdate() {
    this._wasOpen = this.el.open
  },
  updated() {
    if (this._wasOpen) this.el.open = true
  }
}
