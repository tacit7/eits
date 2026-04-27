/**
 * SortDropdown hook
 *
 * Syncs the visible sort label inside a phx-update="ignore" <details> dropdown.
 * LiveView cannot patch the element's children (ignored), but it DOES sync
 * data-* attributes. We read `data-label` and update the .js-sort-label span.
 *
 * Usage:
 *   <details phx-update="ignore" phx-hook="SortDropdown" data-label={@computed_label} ...>
 *     <summary>Sort: <span class="js-sort-label">{@computed_label}</span></summary>
 *   </details>
 */
const SortDropdown = {
  mounted() {
    this.syncLabel()
  },
  updated() {
    this.syncLabel()
  },
  syncLabel() {
    const label = this.el.dataset.label
    const span = this.el.querySelector(".js-sort-label")
    if (span && label) span.textContent = label
  },
}

export default SortDropdown
