<script>
  export let commits = []
  export const live = undefined

  let selectedCommit = commits[0] || null

  $: if (commits.length > 0 && !selectedCommit) {
    selectedCommit = commits[0]
  }
</script>

<div class="grid grid-cols-[40%_60%] gap-4 h-full">
  <!-- Left: Commit List -->
  <div class="overflow-y-auto">
    <div class="space-y-1">
      {#each commits as commit}
        <button
          class="btn btn-ghost w-full justify-start text-left p-3 h-auto"
          class:btn-active={selectedCommit?.commit_hash === commit.commit_hash}
          on:click={() => (selectedCommit = commit)}
        >
          <div class="w-full">
            <div class="font-mono text-xs opacity-70">
              {commit.commit_hash.slice(0, 8)}
            </div>
            <div class="text-sm font-medium mt-1">{commit.commit_message}</div>
            {#if commit.created_at}
              <div class="text-xs opacity-70 mt-1">
                {commit.created_at.slice(0, 16)}
              </div>
            {/if}
          </div>
        </button>
      {/each}
    </div>
  </div>

  <!-- Right: Diff Viewer (placeholder) -->
  <div class="overflow-y-auto border-l border-base-300 pl-4">
    {#if selectedCommit}
      <div class="font-mono text-xs">
        <div class="mb-2 opacity-70">
          Commit: {selectedCommit.commit_hash.slice(0, 8)}
        </div>
        <pre class="whitespace-pre-wrap opacity-70">Git diff viewer coming soon...</pre>
      </div>
    {:else}
      <p class="opacity-70">Select a commit to view diff</p>
    {/if}
  </div>
</div>
