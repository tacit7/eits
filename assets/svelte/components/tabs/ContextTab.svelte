<script>
  export let context = null
</script>

<div class="h-full flex flex-col">
  {#if context?.context}
    <div class="flex-1 overflow-y-auto">
      <div class="prose prose-gray dark:prose-invert max-w-none text-sm">
        <pre class="whitespace-pre-wrap text-gray-900 dark:text-gray-100 bg-transparent border-0 p-0 m-0">{context.context}</pre>
      </div>
    </div>
  {:else}
    <div class="flex-1 flex items-center justify-center">
      <div class="text-center max-w-md">
        <h2 class="text-base font-semibold text-gray-900 dark:text-gray-100">No context saved</h2>
        <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
          Session context will be saved here for resumption.
        </p>
      </div>
    </div>
  {/if}
</div>
