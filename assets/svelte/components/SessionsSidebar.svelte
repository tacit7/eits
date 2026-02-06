<script>
  export let sessions = []
  export let activeSessionId = null
  export let live

  function selectSession(sessionId) {
    live.pushEvent('select_session', { session_id: sessionId })
  }

  function getStatusBadge(session) {
    return session.ended_at && session.ended_at !== '' ? 'ended' : 'active'
  }
</script>

<div class="p-4 h-full flex flex-col">
  <h3 class="text-sm font-semibold mb-3">Sessions</h3>

  <div class="flex-1 overflow-y-auto space-y-2">
    {#each sessions as session}
      <button
        class="w-full text-left p-3 rounded border hover:bg-gray-50 transition-colors"
        class:bg-indigo-50={session.id === activeSessionId}
        class:border-indigo-500={session.id === activeSessionId}
        class:border-gray-200={session.id !== activeSessionId}
        on:click={() => selectSession(session.id)}
      >
        <div class="flex items-center justify-between mb-1">
          <span class="text-sm font-medium truncate">
            {session.name || session.id.slice(0, 11)}
          </span>
          <span
            class="text-xs px-2 py-0.5 rounded"
            class:bg-emerald-100={getStatusBadge(session) === 'active'}
            class:text-emerald-700={getStatusBadge(session) === 'active'}
            class:bg-gray-100={getStatusBadge(session) === 'ended'}
            class:text-gray-600={getStatusBadge(session) === 'ended'}
          >
            {getStatusBadge(session)}
          </span>
        </div>
        <div class="text-xs text-gray-500">
          {session.started_at ? session.started_at.slice(0, 16) : '—'}
        </div>
      </button>
    {/each}
  </div>
</div>
