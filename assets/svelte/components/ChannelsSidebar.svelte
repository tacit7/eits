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
  .sidebar {
    width: 260px;
    height: 100%;
    background: var(--nx-shell);
    display: flex;
    flex-direction: column;
    border-right: 1px solid var(--nx-border);
    position: relative;
    overflow: hidden;
  }

  /* Subtle noise texture overlay */
  .sidebar::before {
    content: '';
    position: absolute;
    inset: 0;
    opacity: 0.03;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='1'/%3E%3C/svg%3E");
    pointer-events: none;
    z-index: 0;
  }

  .sidebar > * {
    position: relative;
    z-index: 1;
  }

  .sidebar-brand {
    padding: 1.25rem 1.25rem 1rem;
    display: flex;
    align-items: center;
    gap: 0.625rem;
  }

  .brand-mark {
    width: 28px;
    height: 28px;
    border-radius: 8px;
    background: linear-gradient(135deg, var(--nx-accent), var(--nx-accent-warm));
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .brand-mark svg {
    width: 14px;
    height: 14px;
    color: #fff;
  }

  .brand-text {
    font-family: 'Bricolage Grotesque', system-ui, sans-serif;
    font-size: 1rem;
    font-weight: 700;
    color: var(--nx-text-primary);
    letter-spacing: -0.02em;
  }

  .section-divider {
    height: 1px;
    background: var(--nx-border);
    margin: 0 1.25rem;
  }

  .section-label {
    padding: 1rem 1.25rem 0.5rem;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.6875rem;
    font-weight: 500;
    color: var(--nx-text-muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .channel-list {
    flex: 1;
    overflow-y: auto;
    padding: 0.25rem 0.5rem;
    scrollbar-width: none;
  }

  .channel-list::-webkit-scrollbar {
    display: none;
  }

  .channel-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 0.75rem;
    margin-bottom: 1px;
    cursor: pointer;
    border-radius: 6px;
    color: var(--nx-text-secondary);
    transition: all 0.15s ease;
    position: relative;
    font-family: 'DM Sans', system-ui, sans-serif;
  }

  .channel-item:hover {
    background: var(--nx-surface);
    color: var(--nx-text-primary);
  }

  .channel-item.active {
    background: var(--nx-accent-soft);
    color: var(--nx-accent);
  }

  .channel-item.active::before {
    content: '';
    position: absolute;
    left: 0;
    top: 50%;
    transform: translateY(-50%);
    width: 3px;
    height: 16px;
    background: var(--nx-accent);
    border-radius: 0 2px 2px 0;
  }

  .channel-name {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.875rem;
    font-weight: 500;
    min-width: 0;
    overflow: hidden;
  }

  .channel-hash {
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.8125rem;
    font-weight: 600;
    opacity: 0.5;
    flex-shrink: 0;
  }

  .channel-item.active .channel-hash {
    opacity: 0.8;
  }

  .channel-label {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .unread-count {
    background: var(--nx-accent);
    color: #fff;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 0.6875rem;
    font-weight: 600;
    padding: 0.0625rem 0.4375rem;
    border-radius: 10px;
    min-width: 18px;
    text-align: center;
    flex-shrink: 0;
  }

  .unread-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--nx-accent);
    flex-shrink: 0;
  }

  /* active-dot and error-dot wired when LiveView passes agent_statuses and channel_errors props */
  .active-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #22c55e;
    flex-shrink: 0;
  }

  .error-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #ef4444;
    flex-shrink: 0;
  }

  .sidebar-footer {
    padding: 0.75rem;
  }

  .new-project-btn {
    width: 100%;
    padding: 0.5rem 0.75rem;
    background: transparent;
    border: 1px dashed var(--nx-border-strong);
    color: var(--nx-text-muted);
    border-radius: 6px;
    cursor: pointer;
    font-family: 'DM Sans', system-ui, sans-serif;
    font-size: 0.8125rem;
    font-weight: 500;
    transition: all 0.15s ease;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.375rem;
  }

  .new-project-btn:hover {
    border-color: var(--nx-text-secondary);
    color: var(--nx-text-secondary);
    background: var(--nx-surface);
  }

  .empty-state {
    padding: 1.25rem;
    text-align: center;
    color: var(--nx-text-muted);
    font-family: 'DM Sans', system-ui, sans-serif;
    font-size: 0.8125rem;
  }
</style>

<div class="sidebar">
  <div class="sidebar-brand">
    <div class="brand-mark">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="3"/>
        <path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/>
      </svg>
    </div>
    <span class="brand-text">Nexus</span>
  </div>

  <div class="section-divider"></div>

  <div class="section-label">Projects</div>

  <div class="channel-list">
    {#if channels && channels.length > 0}
      {#each channels as channel}
        <div
          class="channel-item {isActive(channel.id) ? 'active' : ''}"
          on:click={() => selectChannel(channel.id)}
          on:keydown={(e) => e.key === 'Enter' && selectChannel(channel.id)}
          role="button"
          tabindex="0"
        >
          <div class="channel-name">
            <span class="channel-hash">#</span>
            <span class="channel-label">{channel.name}</span>
          </div>

          {#if getUnreadCount(channel.id) >= 5}
            <span class="unread-count">{getUnreadCount(channel.id)}</span>
          {:else if getUnreadCount(channel.id) > 0}
            <span class="unread-dot" title="{getUnreadCount(channel.id)} unread"></span>
          {/if}
        </div>
      {/each}
    {:else}
      <div class="empty-state">No projects yet</div>
    {/if}
  </div>

  <div class="sidebar-footer">
    <button class="new-project-btn" on:click={() => live.pushEvent('create_channel')}>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
      New Project
    </button>
  </div>
</div>
