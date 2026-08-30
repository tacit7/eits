<script>
  export let logs = []
  export const live = undefined

  let filterLevel = 'all'

  $: filteredLogs =
    filterLevel === 'all' ? logs : logs.filter((log) => log.type === filterLevel)
</script>

<div class="h-full flex flex-col text-base-content">
  <div class="mb-4 inline-flex w-fit items-center gap-1 rounded-box bg-base-200/45 p-0.5">
    <button
      class="h-7 rounded-box px-2 text-mini font-medium transition-colors focus-ring {filterLevel === 'all' ? 'bg-base-100 text-base-content shadow-sm' : 'text-base-content/45 hover:text-base-content/70'}"
      on:click={() => (filterLevel = 'all')}
    >
      All
    </button>
    <button
      class="h-7 rounded-box px-2 text-mini font-medium transition-colors focus-ring {filterLevel === 'info' ? 'bg-base-100 text-base-content shadow-sm' : 'text-base-content/45 hover:text-base-content/70'}"
      on:click={() => (filterLevel = 'info')}
    >
      Info
    </button>
    <button
      class="h-7 rounded-box px-2 text-mini font-medium transition-colors focus-ring {filterLevel === 'error' ? 'bg-base-100 text-error shadow-sm' : 'text-base-content/45 hover:text-base-content/70'}"
      on:click={() => (filterLevel = 'error')}
    >
      Error
    </button>
  </div>

  <div class="flex-1 overflow-y-auto space-y-3">
    {#each filteredLogs as log (log.timestamp + log.message)}
      <div class="text-message rounded-box border border-base-content/8 bg-base-200/35 px-3 py-2">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-mini font-mono tabular-nums text-base-content/35">
            {log.timestamp ? log.timestamp.slice(0, 19) : '-'}
          </span>
          <span class="text-mini px-2 py-0.5 rounded-box bg-base-content/8 text-base-content/50 font-medium">{log.type}</span>
        </div>
        <p class="text-base-content/75 leading-relaxed">{log.message}</p>
      </div>
    {/each}
  </div>
</div>
