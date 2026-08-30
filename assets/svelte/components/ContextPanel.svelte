<script>
  export let sessionContext = null
  export let notes = []
  export let tasks = []
  export let commits = []
  export let logs = []
  export const live = undefined
</script>

<div class="h-full overflow-y-auto p-4 text-message text-base-content">
  <!-- Session Context -->
  <section class="space-y-2" aria-labelledby="context-panel-session-heading">
    <h4 id="context-panel-session-heading" class="text-mini font-semibold text-base-content/45 uppercase tracking-normal">
      Session Context
    </h4>
    {#if sessionContext?.context}
      <div class="rounded-box border border-base-content/8 bg-base-200/60 px-3 py-2 text-message leading-relaxed text-base-content/70 whitespace-pre-wrap">
        {sessionContext.context}
      </div>
    {:else}
      <p class="rounded-box border border-base-content/8 bg-base-200/40 px-3 py-2 text-message text-base-content/35">
        No context available
      </p>
    {/if}
  </section>

  <!-- Notes -->
  <section class="mt-6 space-y-2" aria-labelledby="context-panel-notes-heading">
    <div class="flex items-center justify-between gap-3">
      <h4 id="context-panel-notes-heading" class="text-mini font-semibold text-base-content/45 uppercase tracking-normal">
        Notes
      </h4>
      <span class="font-mono text-mini tabular-nums text-base-content/30">{notes.length}</span>
    </div>
    {#if notes.length > 0}
      <div class="space-y-2">
        {#each notes as note}
          <article class="rounded-box border border-base-content/8 bg-base-200/45 px-3 py-2 shadow-sm">
            <p class="border-l border-primary/35 pl-3 text-message leading-relaxed text-base-content/75">{note.body}</p>
            {#if note.created_at}
              <time class="mt-1.5 block font-mono text-mini tabular-nums text-base-content/30">
                {note.created_at.slice(0, 16)}
              </time>
            {/if}
          </article>
        {/each}
      </div>
    {/if}
  </section>

  <!-- Stats -->
  <section class="mt-6 space-y-2" aria-labelledby="context-panel-stats-heading">
    <h4 id="context-panel-stats-heading" class="text-mini font-semibold text-base-content/45 uppercase tracking-normal">
      Stats
    </h4>
    <dl class="rounded-box border border-base-content/8 bg-base-200/45 px-3 py-2 text-message">
      <div class="flex justify-between">
        <dt class="text-base-content/45">Tasks:</dt>
        <dd class="font-mono tabular-nums text-base-content/70">{tasks.length}</dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-base-content/45">Commits:</dt>
        <dd class="font-mono tabular-nums text-base-content/70">{commits.length}</dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-base-content/45">Logs:</dt>
        <dd class="font-mono tabular-nums text-base-content/70">{logs.length}</dd>
      </div>
    </dl>
  </section>
</div>
