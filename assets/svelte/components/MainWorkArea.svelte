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

<div class="h-full flex flex-col text-base-content">
  <!-- Tab Navigation -->
  <div class="border-b border-base-content/8">
    <nav class="flex px-4" aria-label="Tabs">
      <button
        class="px-4 py-3 text-message font-medium border-b transition-colors focus-ring {activeTab === 'tasks' ? 'border-primary text-primary' : 'border-transparent text-base-content/45'}"
        on:click={() => handleTabChange('tasks')}
      >
        Tasks
      </button>
      <button
        class="px-4 py-3 text-message font-medium border-b transition-colors focus-ring {activeTab === 'commits' ? 'border-primary text-primary' : 'border-transparent text-base-content/45'}"
        on:click={() => handleTabChange('commits')}
      >
        Commits
      </button>
      <button
        class="px-4 py-3 text-message font-medium border-b transition-colors focus-ring {activeTab === 'logs' ? 'border-primary text-primary' : 'border-transparent text-base-content/45'}"
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
