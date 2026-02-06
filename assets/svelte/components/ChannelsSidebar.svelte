<script>
  export let channels = []
  export let activeChannelId = null
  export let unreadCounts = {}
  export let live

  function selectChannel(channelId) {
    live.pushEvent('change_channel', { channel_id: channelId })
  }

  function isActive(channelId) {
    return channelId === activeChannelId
  }

  function getUnreadCount(channelId) {
    return unreadCounts[channelId] || 0
  }
</script>

<style>
  .sidebar-container {
    width: 260px;
    height: 100%;
    background-color: #1a1d21;
    display: flex;
    flex-direction: column;
    border-right: 1px solid #2f3437;
  }

  .sidebar-header {
    padding: 1rem 1.25rem;
    border-bottom: 1px solid #2f3437;
  }

  .project-name {
    font-size: 1.125rem;
    font-weight: 700;
    color: white;
  }

  .channels-section {
    flex: 1;
    overflow-y: auto;
    padding: 1rem 0;
  }

  .section-header {
    padding: 0.5rem 1.25rem;
    font-size: 0.875rem;
    font-weight: 600;
    color: #9ca3af;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .channel-list {
    list-style: none;
    padding: 0;
    margin: 0;
  }

  .channel-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.375rem 1.25rem;
    cursor: pointer;
    color: #9ca3af;
    transition: background-color 0.15s, color 0.15s;
  }

  .channel-item:hover {
    background-color: #222529;
    color: #f8f8f8;
  }

  .channel-item.active {
    background-color: #0f766e;
    color: white;
  }

  .channel-name {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.9375rem;
  }

  .channel-prefix {
    font-weight: 600;
    opacity: 0.7;
  }

  .unread-badge {
    background-color: #e8384f;
    color: white;
    font-size: 0.75rem;
    font-weight: 700;
    padding: 0.125rem 0.5rem;
    border-radius: 1rem;
    min-width: 1.25rem;
    text-align: center;
  }

  .create-channel-btn {
    margin: 0 1.25rem 1rem;
    padding: 0.5rem 1rem;
    background-color: transparent;
    border: 1px solid #2f3437;
    color: #9ca3af;
    border-radius: 0.375rem;
    cursor: pointer;
    font-size: 0.875rem;
    transition: background-color 0.15s, color 0.15s, border-color 0.15s;
  }

  .create-channel-btn:hover {
    background-color: #222529;
    color: #f8f8f8;
    border-color: #6b7280;
  }

  .empty-state {
    padding: 1.25rem;
    text-align: center;
    color: #6b7280;
    font-size: 0.875rem;
  }
</style>

<div class="sidebar-container">
  <!-- Sidebar Header -->
  <div class="sidebar-header">
    <div class="project-name">Eye in the Sky</div>
  </div>

  <!-- Projects Section -->
  <div class="channels-section">
    <div class="section-header">Projects</div>

    {#if channels && channels.length > 0}
      <ul class="channel-list">
        {#each channels as channel}
          <li
            class="channel-item {isActive(channel.id) ? 'active' : ''}"
            on:click={() => selectChannel(channel.id)}
          >
            <div class="channel-name">
              <span>{channel.name}</span>
            </div>

            {#if getUnreadCount(channel.id) > 0}
              <span class="unread-badge">{getUnreadCount(channel.id)}</span>
            {/if}
          </li>
        {/each}
      </ul>
    {:else}
      <div class="empty-state">
        No projects yet
      </div>
    {/if}
  </div>

  <!-- Create Project Button -->
  <button class="create-channel-btn" on:click={() => live.pushEvent('create_channel')}>
    + New Project
  </button>
</div>
