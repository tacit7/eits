<script>
  export let context = null
</script>

<div class="h-full flex flex-col text-base-content">
  {#if context?.context}
    <div class="flex-1 overflow-y-auto">
      <div class="max-w-none text-message">
        <pre class="whitespace-pre-wrap rounded-box border border-base-content/8 bg-base-200/45 p-3 m-0 text-base-content/75 leading-relaxed">{context.context}</pre>
      </div>
    </div>
  {:else}
    <div class="flex-1 flex items-center justify-center">
      <div class="text-center max-w-md">
        <h2 class="text-message font-semibold text-base-content/80">No context saved</h2>
        <p class="mt-1 text-message text-base-content/45">
          Session context will be saved here for resumption.
        </p>
      </div>
    </div>
  {/if}
</div>
