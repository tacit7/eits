export function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

export function highlightMatch(text, query) {
  if (!query) return escapeHtml(text)
  const q = query.toLowerCase()
  const idx = text.toLowerCase().indexOf(q)
  if (idx === -1) return escapeHtml(text)
  return (
    escapeHtml(text.slice(0, idx)) +
    `<mark class="bg-primary/20 text-primary rounded px-0.5">${escapeHtml(text.slice(idx, idx + q.length))}</mark>` +
    escapeHtml(text.slice(idx + q.length))
  )
}

function rowClass() {
  return 'w-full flex items-start gap-3 px-3 py-2 text-left transition-colors text-sm'
}

function rowHTML(item, query, activeFlags) {
  const badge = {
    skill: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-primary/10 text-primary">skill</span>',
    command: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-secondary/10 text-secondary">cmd</span>',
    flag: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-info/10 text-info">flag</span>',
    agent: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-accent/10 text-accent">agent</span>',
    prompt: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-warning/10 text-warning">prompt</span>',
  }[item.type] || ''

  const prefix = item.type === 'agent' ? '@' : '/'
  const nameHtml = highlightMatch(item.slug, query)
  const name = `<span class="font-medium text-base-content">${prefix}${nameHtml}</span>`

  const isActive = item.type === 'flag' && activeFlags && activeFlags[item.slug] !== undefined
  const activeVal = isActive ? activeFlags[item.slug] : null
  const activeBadge = isActive
    ? `<span class="shrink-0 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-success/10 text-success ml-1">${activeVal === true ? 'on' : activeVal === false ? 'off' : escapeHtml(String(activeVal))}</span>`
    : ''

  const desc = item.description
    ? `<span class="text-xs text-base-content/50 truncate">${escapeHtml(item.description)}</span>`
    : ''

  return `
    ${badge}
    <span class="min-w-0 flex-1">
      <span class="flex items-center gap-2">
        ${name}${activeBadge}
      </span>
      ${desc}
    </span>
  `
}

// Render items into container grouped by type. Returns ordered items array (DOM order).
// onHover(idx) and onSelect(idx) are called for mouseenter/mousedown events.
export function renderItems(container, items, activeIndex, query, activeFlags, onHover, onSelect) {
  container.innerHTML = ''

  const groups = {}
  for (const item of items) {
    const t = item.type || 'other'
    if (!groups[t]) groups[t] = []
    groups[t].push(item)
  }

  const typeOrder = ['skill', 'command', 'flag', 'agent', 'prompt']
  const typeLabels = { skill: 'Skills', command: 'Commands', flag: 'Flags', agent: 'Agents', prompt: 'Prompts' }
  const allTypes = [...typeOrder, ...Object.keys(groups).filter(t => !typeOrder.includes(t))]

  const ordered = []

  for (const type of allTypes) {
    if (!groups[type]) continue

    const header = document.createElement('div')
    header.className = 'px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-base-content/40 bg-base-content/[0.02] sticky top-0'
    header.textContent = typeLabels[type] || type
    container.appendChild(header)

    for (const item of groups[type]) {
      const idx = ordered.length
      ordered.push(item)

      const row = document.createElement('button')
      row.type = 'button'
      row.dataset.slashIdx = idx
      row.className = rowClass()
      row.innerHTML = rowHTML(item, query, activeFlags)
      row.addEventListener('mouseenter', () => onHover(idx))
      row.addEventListener('mousedown', (e) => {
        e.preventDefault()
        onSelect(idx)
      })
      container.appendChild(row)
    }
  }

  const hint = document.createElement('div')
  hint.className = 'px-3 py-1.5 text-[10px] text-base-content/30 border-t border-base-content/5 flex items-center gap-3 sticky bottom-0 bg-base-100'
  hint.innerHTML = '<kbd class="font-mono">↑↓</kbd> navigate &nbsp;<kbd class="font-mono">↵</kbd> or <kbd class="font-mono">Tab</kbd> select &nbsp;<kbd class="font-mono">Esc</kbd> dismiss'
  container.appendChild(hint)

  updateActiveItem(container, activeIndex)

  return ordered
}

// Update the highlighted row in container to idx.
export function updateActiveItem(container, idx) {
  const rows = container.querySelectorAll('button[data-slash-idx]')
  rows.forEach(row => {
    const rowIdx = parseInt(row.dataset.slashIdx)
    if (rowIdx === idx) {
      row.classList.add('bg-base-content/[0.06]')
      row.scrollIntoView({ block: 'nearest' })
    } else {
      row.classList.remove('bg-base-content/[0.06]')
    }
  })
}
