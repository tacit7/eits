<script>
  import { formatDateRelative, shortId } from '../../utils/datetime.js'
  import { formatUUID, copyToClipboard } from '../../utils/clipboard.js'

  // Heroicons
  import CheckSvg from 'heroicons/24/outline/check.svg'
  import CalendarSvg from 'heroicons/24/outline/calendar-days.svg'
  import PencilSvg from 'heroicons/24/outline/pencil-square.svg'
  import TrashSvg from 'heroicons/24/outline/trash.svg'
  import ClipboardSvg from 'heroicons/24/outline/clipboard-document.svg'

  export let tasks = []
  export const live = undefined

  let selectedTask = null
  let hoveredTask = null

  function getPriorityFlag(priority) {
    if (priority >= 70) return { color: '#d1453b', icon: '🚩', label: 'P1' }
    if (priority >= 40) return { color: '#eb8909', icon: '🔶', label: 'P2' }
    if (priority >= 20) return { color: '#246fe0', icon: '🔵', label: 'P3' }
    return { color: '#808080', icon: '⚪', label: 'P4' }
  }

  function isOverdue(dateStr) {
    if (!dateStr) return false
    return new Date(dateStr) < new Date()
  }

  function handleTaskClick(task) {
    selectedTask = selectedTask?.id === task.id ? null : task
  }

  function toggleComplete(task, event) {
    event.stopPropagation()
    // TODO: Implement task completion via live push
    console.log('Toggle complete:', task.id)
  }

  function handleCopyId(id, event) {
    event.stopPropagation()
    copyToClipboard(formatUUID(id), { formatAsUUID: false })
  }
</script>

<div class="max-w-4xl mx-auto">
  <!-- Task List -->
  <div class="space-y-0">
    {#each tasks as task}
      {@const priority = getPriorityFlag(task.priority)}
      {@const dueDate = formatDateRelative(task.due_at)}
      {@const overdue = isOverdue(task.due_at)}

      <div
        class="group relative border-b border-base-200 hover:bg-base-200/50 transition-colors cursor-pointer"
        role="button"
        tabindex="0"
        on:click={() => handleTaskClick(task)}
        on:keydown={(e) => e.key === 'Enter' && handleTaskClick(task)}
        on:mouseenter={() => hoveredTask = task.id}
        on:mouseleave={() => hoveredTask = null}
      >
        <div class="flex items-start gap-3 py-3 px-4">
          <!-- Checkbox -->
          <button
            class="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full border-2 border-base-content/30 hover:border-primary transition-colors flex items-center justify-center"
            on:click={(e) => toggleComplete(task, e)}
            aria-label="Complete task"
          >
            {#if task.state_name === 'done' || task.completed_at}
              <span class="w-3.5 h-3.5 text-success">{@html CheckSvg}</span>
            {/if}
          </button>

          <!-- Task Content -->
          <div class="flex-1 min-w-0">
            <div class="flex items-start justify-between gap-2">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <h3 class="text-sm font-normal text-base-content group-hover:text-base-content/90 {task.completed_at ? 'line-through opacity-60' : ''}">
                    {task.title}
                  </h3>
                  {#if task.priority >= 20}
                    <span
                      class="flex-shrink-0 text-xs"
                      style="color: {priority.color}"
                      title="{priority.label} priority"
                    >
                      🚩
                    </span>
                  {/if}
                </div>

                {#if task.description && selectedTask?.id === task.id}
                  <p class="text-xs text-base-content/60 mt-1 whitespace-pre-wrap">
                    {task.description}
                  </p>
                {/if}

                <!-- Task Meta -->
                <div class="flex items-center gap-3 mt-2 text-xs text-base-content/50">
                  <!-- Task ID Badge -->
                  <button
                    class="badge badge-ghost badge-xs hover:badge-primary cursor-pointer font-mono transition-colors"
                    on:click={(e) => handleCopyId(task.id, e)}
                    title="Copy ID: {task.id}"
                  >
                    #{shortId(task.id, 8)}
                  </button>

                  {#if dueDate}
                    <span class="flex items-center gap-1 {overdue ? 'text-error' : ''}">
                      <span class="w-3.5 h-3.5">{@html CalendarSvg}</span>
                      {dueDate}
                    </span>
                  {/if}

                  {#if task.state_name}
                    <span class="badge badge-ghost badge-xs">
                      {task.state_name}
                    </span>
                  {/if}

                  {#if task.tags && task.tags.length > 0}
                    <div class="flex items-center gap-1">
                      {#each task.tags as tag}
                        <span class="badge badge-outline badge-xs">
                          {tag.name}
                        </span>
                      {/each}
                    </div>
                  {/if}
                </div>
              </div>

              <!-- Actions (visible on hover) -->
              {#if hoveredTask === task.id || selectedTask?.id === task.id}
                <div class="flex items-center gap-1 flex-shrink-0">
                  <button
                    class="btn btn-ghost btn-xs btn-square"
                    on:click={(e) => {e.stopPropagation()}}
                    title="Edit task"
                  >
                    <span class="w-4 h-4">{@html PencilSvg}</span>
                  </button>
                  <button
                    class="btn btn-ghost btn-xs btn-square text-error/70 hover:text-error"
                    on:click={(e) => {e.stopPropagation()}}
                    title="Delete task"
                  >
                    <span class="w-4 h-4">{@html TrashSvg}</span>
                  </button>
                </div>
              {/if}
            </div>
          </div>
        </div>
      </div>
    {/each}

    {#if !tasks || tasks.length === 0}
      <div class="text-center py-12">
        <div class="text-base-content/40 mb-2">
          <span class="w-12 h-12 mx-auto block">{@html ClipboardSvg}</span>
        </div>
        <h3 class="text-sm font-medium text-base-content/60 mb-1">No tasks yet</h3>
        <p class="text-xs text-base-content/40">Click "New Task" to get started</p>
      </div>
    {/if}
  </div>
</div>

<style>
  .badge-xs {
    font-size: 0.65rem;
    padding: 0.125rem 0.375rem;
  }
</style>
