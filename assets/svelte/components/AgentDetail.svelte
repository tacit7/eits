<script>
  import { onMount, onDestroy } from "svelte"
  import TasksTab from "./tabs/TasksTab.svelte"
  import CommitsTab from "./tabs/CommitsTab.svelte"
  import LogsTab from "./tabs/LogsTab.svelte"
  import ContextTab from "./tabs/ContextTab.svelte"
  import NotesTab from "./tabs/NotesTab.svelte"
  import MessagesTab from "./tabs/MessagesTab.svelte"
  import { parseDateLike, relativeFrom, elapsedTime, shortId } from "../utils/datetime.js"
  import { emptyStateStyle } from "../utils/styles.js"

  // Heroicons SVG files
  import ChatBubbleLeftSvg from 'heroicons/24/outline/chat-bubble-left.svg'
  import HeartSvg from 'heroicons/24/outline/heart.svg'
  import TrashSvg from 'heroicons/24/outline/trash.svg'
  import CheckSvg from 'heroicons/24/outline/check.svg'
  import SunSvg from 'heroicons/24/outline/sun.svg'
  import MoonSvg from 'heroicons/24/outline/moon.svg'

  function statusToBadgeVariant(status) {
    const map = {
      active: 'badge-success',
      working: 'badge-warning',
      idle: 'badge-info',
      stale: 'badge-warning badge-outline',
      completed: 'badge-ghost',
      failed: 'badge-error'
    }
    return map[status] || 'badge-ghost'
  }

  export let header
  export let activeTab
  export let counts
  export let tasks
  export let commits
  export let logs
  export let context
  export let notes
  export let messages
  export let live
  export let showNoteModal = false
  export let showTaskModal = false

  const tabs = [
    {
      key: "tasks",
      label: "Tasks",
      countKey: "tasks",
      icon: "M2.5 1.75v11.5c0 .138.112.25.25.25h3.17a.75.75 0 0 1 .75.75V16L9.4 13.571c.13-.096.289-.196.601-.196h3.249a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H2.75a.25.25 0 0 0-.25.25Zm-1.5 0C1 .784 1.784 0 2.75 0h10.5C14.216 0 15 .784 15 1.75v11.5A1.75 1.75 0 0 1 13.25 15H10l-3.573 2.573A1.458 1.458 0 0 1 4 16.543V15H2.75A1.75 1.75 0 0 1 1 13.25Z"
    },
    {
      key: "commits",
      label: "Commits",
      countKey: "commits",
      icon: "M11.93 8.5a4.002 4.002 0 0 1-7.86 0H.75a.75.75 0 0 1 0-1.5h3.32a4.002 4.002 0 0 1 7.86 0h3.32a.75.75 0 0 1 0 1.5Zm-1.43-.75a2.5 2.5 0 1 0-5 0 2.5 2.5 0 0 0 5 0Z"
    },
    {
      key: "logs",
      label: "Logs",
      countKey: "logs",
      icon: "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25ZM3.5 4.75A.75.75 0 0 1 4.25 4h7.5a.75.75 0 0 1 0 1.5h-7.5A.75.75 0 0 1 3.5 4.75ZM4.25 7a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5ZM3.5 10.75a.75.75 0 0 1 .75-.75h7.5a.75.75 0 0 1 0 1.5h-7.5a.75.75 0 0 1-.75-.75Z"
    },
    {
      key: "context",
      label: "Context",
      countKey: null,
      icon: "M0 1.75C0 .784.784 0 1.75 0h8.5C11.216 0 12 .784 12 1.75v12.5c0 .085-.006.168-.018.25h2.268a.25.25 0 0 0 .25-.25V8.285a.25.25 0 0 0-.111-.208l-1.055-.703a.749.749 0 1 1 .832-1.248l1.055.703c.487.325.779.871.779 1.456v5.965A1.75 1.75 0 0 1 14.25 16h-3.5a.766.766 0 0 1-.197-.026c-.099.017-.2.026-.303.026h-3a.75.75 0 0 1-.75-.75V14h-1v1.25a.75.75 0 0 1-.75.75H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25H4v-1.25a.75.75 0 0 1 .75-.75h2a.75.75 0 0 1 .75.75v1.25h2.25a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25Z"
    },
    {
      key: "notes",
      label: "Notes",
      countKey: "notes",
      icon: "M0 3.75C0 2.784.784 2 1.75 2h12.5c.966 0 1.75.784 1.75 1.75v8.5A1.75 1.75 0 0 1 14.25 14H1.75A1.75 1.75 0 0 1 0 12.25Zm1.75-.25a.25.25 0 0 0-.25.25v8.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25v-8.5a.25.25 0 0 0-.25-.25ZM3.5 6.25a.75.75 0 0 1 .75-.75h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1-.75-.75Zm.75 2.25a.75.75 0 0 0 0 1.5h4a.75.75 0 0 0 0-1.5Z"
    },
    {
      key: "messages",
      label: "Messages",
      countKey: "messages",
      icon: "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Z"
    },
  ]

  function countFor(key) {
    return counts?.[key] || 0
  }

  let tick = 0
  let intervalId

  onMount(() => {
    // Only start the interval if status is active
    if (header.status === 'active') {
      intervalId = setInterval(() => tick++, 1000)
    }
  })

  onDestroy(() => {
    if (intervalId) {
      clearInterval(intervalId)
    }
  })

  function changeTab(tab) {
    live.pushEvent("change_tab", { tab })
  }

  let copied = false
  let copiedTimeout

  function copySessionId() {
    navigator.clipboard.writeText(header.session_id).then(() => {
      copied = true
      if (copiedTimeout) clearTimeout(copiedTimeout)
      copiedTimeout = setTimeout(() => {
        copied = false
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy session ID:', err)
    })
  }
</script>

<div class="min-h-screen bg-base-200">
  <div class="mx-auto max-w-6xl px-6 py-6">
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <!-- Header -->
        <div class="bg-base-100/80 backdrop-blur sticky top-0 z-30 border-b border-base-300 -m-6 mb-0 p-6">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h1 class="text-2xl font-semibold text-gray-900 dark:text-gray-100">{header.agent_type}</h1>

              <span class="badge badge-outline font-mono">
                {shortId(header.agent_id)}
              </span>

              <span class="badge {statusToBadgeVariant(header.status)}" aria-label={`Status: ${header.status}`}>
                {header.status}
              </span>
            </div>

            <!-- Meta chips -->
            <div class="mt-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2 text-xs sm:text-sm">
              <div class="bg-base-200 rounded-lg px-3 py-1.5 flex items-center justify-between gap-2">
                <div>
                  <span class="text-base-content/70 font-medium">Session</span>
                  <span class="ml-2 font-mono font-semibold">#{shortId(header.session_id)}</span>
                </div>
                <button
                  on:click={copySessionId}
                  class="btn btn-ghost btn-xs btn-circle {copied ? 'btn-success' : ''}"
                  title={copied ? 'Copied!' : 'Copy full session ID'}
                  aria-label="Copy session ID"
                >
                  {#if copied}
                    <span class="h-4 w-4">{@html CheckSvg}</span>
                  {:else}
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                    </svg>
                  {/if}
                </button>
              </div>

              <div class="bg-base-200 rounded-lg px-3 py-1.5">
                <span class="text-base-content/70 font-medium">Project</span>
                <span class="ml-2 font-semibold">{header.project ?? "Unassigned"}</span>
              </div>

              {#if header.started}
                <div class="bg-base-200 rounded-lg px-3 py-1.5">
                  <span class="text-base-content/70 font-medium">Started</span>
                  <time datetime={parseDateLike(header.started)?.toISOString()} title={String(header.started) + " UTC"} class="ml-2 font-semibold">
                    {relativeFrom(parseDateLike(header.started))}
                  </time>
                </div>
              {/if}

              <div class="bg-base-200 rounded-lg px-3 py-1.5">
                <span class="text-base-content/70 font-medium">Duration</span>
                <span class="ml-2 font-semibold">
                  {#if header.status === 'active'}
                    {tick >= 0 ? elapsedTime(parseDateLike(header.started)) : '—'}
                  {:else}
                    {header.duration ?? '—'}
                  {/if}
                </span>
              </div>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <!-- Action Buttons (💬 ❤️ 🗑️) -->
            {#if header.can_chat}
              <button
                class="btn btn-ghost btn-sm text-base-content/40 hover:text-info transition-colors"
                title="Open chat"
                aria-label="Open chat"
                on:click={() => live.pushEvent('open_chat', { session_id: header.session_id })}
              >
                <span class="h-4 w-4">{@html ChatBubbleLeftSvg}</span>
              </button>
            {/if}

            {#if header.can_bookmark}
              <button
                class="btn btn-ghost btn-sm text-base-content/40 hover:text-warning transition-colors"
                title="Bookmark agent"
                aria-label="Bookmark agent"
                on:click={() => live.pushEvent('toggle_bookmark', { agent_id: header.agent_id })}
              >
                <span class="h-4 w-4">{@html HeartSvg}</span>
              </button>
            {/if}

            {#if header.can_archive}
              <button
                class="btn btn-ghost btn-sm text-base-content/40 hover:text-warning transition-colors"
                title="Archive session"
                aria-label="Archive session"
                on:click={() => {
                  if (confirm('Archive this session?')) {
                    live.pushEvent('archive_session', { session_id: header.session_id })
                  }
                }}
              >
                <span class="h-4 w-4">{@html TrashSvg}</span>
              </button>
            {/if}

            <label class="swap swap-rotate btn btn-ghost btn-sm btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <!-- sun icon -->
              <span class="swap-on h-5 w-5">{@html SunSvg}</span>
              <!-- moon icon -->
              <span class="swap-off h-5 w-5">{@html MoonSvg}</span>
            </label>

            <button
              class="btn btn-primary btn-sm"
              on:click={() => {
                if (confirm('Are you sure you want to end this session?')) {
                  live.pushEvent('end_session')
                }
              }}
              disabled={header.status === 'completed' || header.status === 'failed'}
              aria-label="End session"
            >
              End Session
            </button>
            <button
              class="btn btn-error btn-outline btn-sm"
              on:click={() => {
                if (confirm('Are you sure you want to delete this session? This action cannot be undone.')) {
                  live.pushEvent('delete_session')
                }
              }}
              aria-label="Delete session"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="currentColor" viewBox="0 0 16 16">
                <path d="M5.5 5.5A.5.5 0 0 1 6 6v6a.5.5 0 0 1-1 0V6a.5.5 0 0 1 .5-.5zm2.5 0a.5.5 0 0 1 .5.5v6a.5.5 0 0 1-1 0V6a.5.5 0 0 1 .5-.5zm3 .5a.5.5 0 0 0-1 0v6a.5.5 0 0 0 1 0V6z"/>
                <path fill-rule="evenodd" d="M14.5 3a1 1 0 0 1-1 1H13v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V4h-.5a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1H6a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1h3.5a1 1 0 0 1 1 1v1zM4.118 4 4 4.059V13a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V4.059L11.882 4H4.118zM2.5 1v1h11V1h-11z"/>
              </svg>
              Delete
            </button>
            <button
              class="btn btn-outline btn-sm"
              on:click={() => live.pushEvent('new_task')}
              aria-label="Create new task"
            >
              New Task
            </button>
            <button
              class="btn btn-outline btn-sm"
              on:click={() => live.pushEvent('add_note')}
              aria-label="Add note"
            >
              Add Note
            </button>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div class="border-b border-base-300">
        <div class="px-6">
          <div role="tablist" aria-label="Session sections" class="flex items-center gap-1 -mb-px">
            {#each tabs as t}
              <button
                role="tab"
                id={`tab-${t.key}`}
                aria-selected={activeTab === t.key}
                aria-controls={`panel-${t.key}`}
                class="flex items-center gap-2 px-4 py-2 border-b-2 text-sm transition-colors {activeTab === t.key ? 'border-primary font-medium text-base-content' : 'border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/20'}"
                on:click={() => changeTab(t.key)}
              >
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
                  <path d={t.icon} />
                </svg>
                <span>{t.label}</span>
                {#if t.countKey && countFor(t.countKey) > 0}
                  <span class="badge badge-sm badge-ghost">
                    {countFor(t.countKey)}
                  </span>
                {/if}
              </button>
            {/each}
          </div>
        </div>
      </div>

      <!-- Content -->
      <div role="tabpanel" id={`panel-${activeTab}`} aria-labelledby={`tab-${activeTab}`} class="px-6 py-6">
        {#if activeTab === "tasks"}
          <TasksTab {tasks} />
        {:else if activeTab === "commits"}
          <CommitsTab {commits} />
        {:else if activeTab === "logs"}
          <LogsTab {logs} />
        {:else if activeTab === "context"}
          <ContextTab {context} />
        {:else if activeTab === "notes"}
          <NotesTab {notes} />
        {:else if activeTab === "messages"}
          <MessagesTab {messages} {live} />
        {/if}
      </div>
      </div>
    </div>
  </div>
</div>

<!-- Add Note Modal -->
<dialog class="modal {showNoteModal ? 'modal-open' : ''}">
  <div class="modal-box">
    <form method="dialog">
      <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2" on:click={() => live.pushEvent('close_modal')}>✕</button>
    </form>
    <h3 class="font-bold text-lg mb-4">Add Note</h3>
    <form on:submit|preventDefault={(e) => {
      const formData = new FormData(e.target);
      live.pushEvent('save_note', { body: formData.get('body') });
    }}>
      <div class="form-control">
        <label class="label" for="note-body">
          <span class="label-text">Note Content (Markdown supported)</span>
        </label>
        <textarea
          id="note-body"
          name="body"
          class="textarea textarea-bordered h-48"
          placeholder="Enter your note here... You can use markdown formatting."
          required
        ></textarea>
      </div>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" on:click={() => live.pushEvent('close_modal')}>
          Cancel
        </button>
        <button type="submit" class="btn btn-primary">
          Save Note
        </button>
      </div>
    </form>
  </div>
  <form method="dialog" class="modal-backdrop">
    <button on:click={() => live.pushEvent('close_modal')}>close</button>
  </form>
</dialog>

<!-- Add Task Modal -->
<dialog class="modal {showTaskModal ? 'modal-open' : ''}">
  <div class="modal-box">
    <form method="dialog">
      <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2" on:click={() => live.pushEvent('close_modal')}>✕</button>
    </form>
    <h3 class="font-bold text-lg mb-4">Create New Task</h3>
    <form on:submit|preventDefault={(e) => {
      const formData = new FormData(e.target);
      live.pushEvent('save_task', {
        title: formData.get('title'),
        description: formData.get('description')
      });
    }}>
      <div class="form-control mb-4">
        <label class="label" for="task-title">
          <span class="label-text">Title</span>
        </label>
        <input
          id="task-title"
          name="title"
          type="text"
          class="input input-bordered"
          placeholder="Task title"
          required
        />
      </div>
      <div class="form-control">
        <label class="label" for="task-description">
          <span class="label-text">Description</span>
        </label>
        <textarea
          id="task-description"
          name="description"
          class="textarea textarea-bordered h-32"
          placeholder="Optional task description"
        ></textarea>
      </div>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" on:click={() => live.pushEvent('close_modal')}>
          Cancel
        </button>
        <button type="submit" class="btn btn-primary">
          Create Task
        </button>
      </div>
    </form>
  </div>
  <form method="dialog" class="modal-backdrop">
    <button on:click={() => live.pushEvent('close_modal')}>close</button>
  </form>
</dialog>
