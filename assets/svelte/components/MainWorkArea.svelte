<script>
  import TasksTab from './tabs/TasksTab.svelte'
  import CommitsTab from './tabs/CommitsTab.svelte'
  import LogsTab from './tabs/LogsTab.svelte'

  export let activeTab = 'tasks'
  export let tasks = []
  export let commits = []
  export let logs = []
  export let live

  function handleTabChange(tab) {
    live.pushEvent('change_tab', { tab })
  }
</script>

<div class="h-full flex flex-col">
  <!-- Tab Navigation -->
  <div class="border-b border-gray-200">
    <nav class="flex px-4" aria-label="Tabs">
      <button
        class="px-4 py-3 text-sm font-medium border-b-2 transition-colors"
        class:border-indigo-500={activeTab === 'tasks'}
        class:text-indigo-600={activeTab === 'tasks'}
        class:border-transparent={activeTab !== 'tasks'}
        class:text-gray-500={activeTab !== 'tasks'}
        on:click={() => handleTabChange('tasks')}
      >
        Tasks
      </button>
      <button
        class="px-4 py-3 text-sm font-medium border-b-2 transition-colors"
        class:border-indigo-500={activeTab === 'commits'}
        class:text-indigo-600={activeTab === 'commits'}
        class:border-transparent={activeTab !== 'commits'}
        class:text-gray-500={activeTab !== 'commits'}
        on:click={() => handleTabChange('commits')}
      >
        Commits
      </button>
      <button
        class="px-4 py-3 text-sm font-medium border-b-2 transition-colors"
        class:border-indigo-500={activeTab === 'logs'}
        class:text-indigo-600={activeTab === 'logs'}
        class:border-transparent={activeTab !== 'logs'}
        class:text-gray-500={activeTab !== 'logs'}
        on:click={() => handleTabChange('logs')}
      >
        Logs
      </button>
    </nav>
  </div>

  <!-- Tab Content -->
  <div class="flex-1 overflow-hidden p-4">
    {#if activeTab === 'tasks'}
      <TasksTab {tasks} {live} />
    {:else if activeTab === 'commits'}
      <CommitsTab {commits} {live} />
    {:else if activeTab === 'logs'}
      <LogsTab {logs} {live} />
    {/if}
  </div>
</div>
