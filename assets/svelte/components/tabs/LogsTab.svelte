<script>
  export let logs = []
  export let live

  let filterLevel = 'all'

  $: filteredLogs =
    filterLevel === 'all' ? logs : logs.filter((log) => log.type === filterLevel)
</script>

<div class="h-full flex flex-col">
  <div class="btn-group mb-4">
    <button
      class="btn btn-sm"
      class:btn-active={filterLevel === 'all'}
      on:click={() => (filterLevel = 'all')}
    >
      All
    </button>
    <button
      class="btn btn-sm"
      class:btn-active={filterLevel === 'info'}
      on:click={() => (filterLevel = 'info')}
    >
      Info
    </button>
    <button
      class="btn btn-sm"
      class:btn-active={filterLevel === 'error'}
      on:click={() => (filterLevel = 'error')}
    >
      Error
    </button>
  </div>

  <div class="flex-1 overflow-y-auto space-y-3">
    {#each filteredLogs as log}
      <div class="text-sm">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-xs font-mono text-gray-500">
            {log.timestamp ? log.timestamp.slice(0, 19) : '—'}
          </span>
          <span class="text-xs px-2 py-0.5 rounded bg-gray-100">{log.type}</span>
        </div>
        <p>{log.message}</p>
      </div>
    {/each}
  </div>
</div>
