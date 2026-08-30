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

<div class="p-4 h-full flex flex-col text-base-content">
  <h3 class="text-mini font-semibold text-base-content/45 uppercase tracking-normal mb-3">Sessions</h3>

  <div class="flex-1 overflow-y-auto space-y-2">
    {#each sessions as session (session.id)}
      <button
        class="w-full text-left p-3 rounded-box border transition-colors focus-ring {session.id === activeSessionId ? 'bg-primary/8 border-primary/30' : 'border-base-content/8 hover:bg-base-content/[0.04]'}"
        on:click={() => selectSession(session.id)}
      >
        <div class="flex items-center justify-between mb-1">
          <span class="text-message font-medium truncate text-base-content/80">
            {session.name || session.id.slice(0, 11)}
          </span>
          <span
            class="text-mini px-2 py-0.5 rounded-box font-medium {getStatusBadge(session) === 'active' ? 'bg-success/12 text-success' : 'bg-base-content/8 text-base-content/45'}"
          >
            {getStatusBadge(session)}
          </span>
        </div>
        <div class="font-mono text-mini tabular-nums text-base-content/35">
          {session.started_at ? session.started_at.slice(0, 16) : '-'}
        </div>
      </button>
    {/each}
  </div>
</div>
