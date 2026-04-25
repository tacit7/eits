/**
 * ShiftSelect
 *
 * Wraps the sessions list. Uses a single capture-phase listener to:
 * - Track the anchor row on normal checkbox clicks.
 * - Fire `select_range` on shift+click and cancel the phx-click handler.
 *
 * Capture phase is required because the checkbox has onclick="event.stopPropagation()"
 * to prevent row navigation. A bubble-phase listener on a wrapper would never see
 * the click. The capture handler runs before that stop fires.
 *
 * Usage:
 *   <div phx-hook="ShiftSelect" id="ps-list-shift-wrapper">
 *     <div id="ps-list" phx-update="stream" ...>
 *       <div data-row-id="123" ...>
 *         ...  (square_checkbox renders data-checkbox-area="true" on the label)
 *       </div>
 *     </div>
 *   </div>
 */
export const ShiftSelect = {
  mounted() {
    this._anchor = null

    this._onClick = (e) => {
      const checkboxArea = e.target.closest("[data-checkbox-area]")
      if (!checkboxArea || !this.el.contains(checkboxArea)) return

      const row = e.target.closest("[data-row-id]")
      if (!row || !this.el.contains(row)) return

      const id = row.dataset.rowId
      if (!id) return

      if (!e.shiftKey) {
        // Normal click — update anchor; let phx-click="toggle_select" handle the toggle
        this._anchor = id
        return
      }

      // Shift-click — fire range event
      if (!this._anchor || this._anchor === id) {
        this._anchor = id
        return
      }

      // Scope to #ps-list to avoid picking up stray data-row-id elements
      const list = this.el.querySelector("#ps-list")
      if (!list) return

      const orderedIds = Array.from(
        list.querySelectorAll("[data-row-id]")
      ).map((el) => el.dataset.rowId)

      this.pushEvent("select_range", {
        anchor_id: this._anchor,
        target_id: id,
        ordered_ids: orderedIds,
      })

      // Update anchor for chained shift-clicks
      this._anchor = id

      // stopPropagation prevents the event reaching LiveView's bubble-phase phx-click handler.
      e.stopPropagation()
      e.stopImmediatePropagation()
      e.preventDefault()
    }

    this.el.addEventListener("click", this._onClick, true)
  },

  updated() {
    // After a LiveView patch (filter change, PubSub update), reset the anchor
    // if the anchored row is no longer in the DOM.
    if (this._anchor) {
      const list = this.el.querySelector("#ps-list")
      if (list && !list.querySelector(`[data-row-id="${this._anchor}"]`)) {
        this._anchor = null
      }
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick, true)
  },
}
