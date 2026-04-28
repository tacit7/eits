// DmHistoryCleanup: mounted on the sessions page.
// Receives push_event("evict-dm-history", %{uuids: [...]}) from the server
// after sessions are archived (single or bulk). Writes a localStorage sentinel
// that triggers the `storage` event in other open tabs so they can evict their
// dm_history:<uuid> entries. Also cleans up in the current tab directly.
export const DmHistoryCleanup = {
  mounted() {
    this.handleEvent('evict-dm-history', ({ uuids }) => {
      if (!Array.isArray(uuids) || uuids.length === 0) return
      try {
        // Clean up in this tab
        uuids.forEach(uuid => localStorage.removeItem(`dm_history:${uuid}`))
        // Signal other tabs via the storage event (write + immediate delete)
        localStorage.setItem('dm_history_evict', JSON.stringify(uuids))
        localStorage.removeItem('dm_history_evict')
      } catch {}
    })
  },
  destroyed() {}
}
