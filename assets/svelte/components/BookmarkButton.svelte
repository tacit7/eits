<script>
  export let bookmarkType;  // 'file' | 'note' | 'agent' | 'session' | 'task'
  export let bookmarkId = null;
  export let filePath = null;
  export let lineNumber = null;
  export let title = null;
  export let category = null;
  export let projectId = null;
  export let agentId = null;
  export let isBookmarked = false;
  export let size = 'sm';  // 'xs' | 'sm' | 'md' | 'lg'
  export let showLabel = false;

  let loading = false;
  let currentBookmarkId = bookmarkId;

  async function toggleBookmark() {
    loading = true;

    const payload = {
      bookmark_type: bookmarkType,
      bookmark_id: bookmarkId,
      file_path: filePath,
      line_number: lineNumber,
      title: title,
      category: category,
      project_id: projectId,
      agent_id: agentId
    };

    try {
      if (isBookmarked && currentBookmarkId) {
        // Delete bookmark
        const response = await fetch(`/api/bookmarks/${currentBookmarkId}`, {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json' }
        });

        if (response.ok) {
          isBookmarked = false;
          currentBookmarkId = null;
        }
      } else {
        // Create bookmark
        const response = await fetch('/api/bookmarks', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (response.ok) {
          const data = await response.json();
          isBookmarked = true;
          currentBookmarkId = data.id;
        }
      }
    } catch (error) {
      console.error('Bookmark error:', error);
    } finally {
      loading = false;
    }
  }

  const sizeClasses = {
    xs: 'w-3 h-3',
    sm: 'w-4 h-4',
    md: 'w-5 h-5',
    lg: 'w-6 h-6'
  };

  const buttonSizeClasses = {
    xs: 'btn-xs',
    sm: 'btn-sm',
    md: 'btn-md',
    lg: 'btn-lg'
  };
</script>

<button
  on:click={toggleBookmark}
  disabled={loading}
  class="btn btn-ghost {buttonSizeClasses[size]} {showLabel ? 'gap-2' : 'btn-square'} hover:bg-base-200 transition-colors"
  title={isBookmarked ? 'Remove bookmark' : 'Add bookmark'}
>
  {#if loading}
    <span class="loading loading-spinner {sizeClasses[size]}"></span>
  {:else if isBookmarked}
    <svg class="{sizeClasses[size]} text-warning" fill="currentColor" viewBox="0 0 20 20">
      <!-- Filled bookmark -->
      <path d="M5 4a2 2 0 012-2h6a2 2 0 012 2v14l-5-2.5L5 18V4z"/>
    </svg>
  {:else}
    <svg class="{sizeClasses[size]} text-base-content/40 hover:text-base-content/70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <!-- Outline bookmark -->
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"/>
    </svg>
  {/if}

  {#if showLabel}
    <span class="text-xs">{isBookmarked ? 'Bookmarked' : 'Bookmark'}</span>
  {/if}
</button>

<style>
  button {
    padding: 0.25rem;
  }
</style>
