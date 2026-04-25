/**
 * IndeterminateCheckbox
 *
 * Keeps the native `input.indeterminate` DOM property in sync with the
 * `data-indeterminate` attribute rendered by the server. The indeterminate
 * state cannot be set via HTML attributes — it requires a JS property set.
 *
 * Usage: attach to a checkbox input with an id, e.g.:
 *   <input id="my-cb" type="checkbox" data-indeterminate="true" phx-hook="IndeterminateCheckbox" />
 */
export const IndeterminateCheckbox = {
  mounted() {
    this._sync()
  },

  updated() {
    this._sync()
  },

  _sync() {
    this.el.indeterminate = this.el.dataset.indeterminate === "true"
  },
}
