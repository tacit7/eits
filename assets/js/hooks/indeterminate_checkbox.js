/**
 * IndeterminateCheckbox
 *
 * Sets the native `indeterminate` property on a checkbox input based on a
 * `data-indeterminate` attribute. The indeterminate state cannot be set via
 * HTML alone — it requires JavaScript.
 *
 * Usage:
 *   <input type="checkbox"
 *          phx-hook="IndeterminateCheckbox"
 *          data-indeterminate={some_partial_selection_bool} />
 */
export const IndeterminateCheckbox = {
  mounted() {
    this.sync()
  },
  updated() {
    this.sync()
  },
  sync() {
    this.el.indeterminate = this.el.dataset.indeterminate === "true"
  }
}
