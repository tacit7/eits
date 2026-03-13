<script>
  export let sessionContext = null
  export let notes = []
  export let tasks = []
  export let commits = []
  export let logs = []
  export const live = undefined
</script>

<div class="p-4 space-y-6 h-full overflow-y-auto">
  <!-- Session Context -->
  <div>
    <h4 class="text-sm font-semibold mb-2">Session Context</h4>
    {#if sessionContext?.context}
      <div class="text-sm text-gray-600 whitespace-pre-wrap">
        {sessionContext.context}
      </div>
    {:else}
      <p class="text-sm text-gray-500">No context available</p>
    {/if}
  </div>

  <!-- Notes -->
  <div>
    <h4 class="text-sm font-semibold mb-2">Notes ({notes.length})</h4>
    {#if notes.length > 0}
      <div class="space-y-2 mb-3">
        {#each notes as note}
          <div class="border-l-2 border-indigo-200 pl-3 py-1">
            <p class="text-sm">{note.body}</p>
            {#if note.created_at}
              <span class="text-xs text-gray-500">{note.created_at.slice(0, 16)}</span>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Stats -->
  <div>
    <h4 class="text-sm font-semibold mb-2">Stats</h4>
    <dl class="space-y-1 text-sm">
      <div class="flex justify-between">
        <dt class="text-gray-500">Tasks:</dt>
        <dd class="font-mono">{tasks.length}</dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-gray-500">Commits:</dt>
        <dd class="font-mono">{commits.length}</dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-gray-500">Logs:</dt>
        <dd class="font-mono">{logs.length}</dd>
      </div>
    </dl>
  </div>
</div>
