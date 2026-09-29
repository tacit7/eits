import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'
import { mount, tick, unmount } from 'svelte'

import AgentMessagesPanel from './AgentMessagesPanel.svelte'

let component
const originalShowModal = HTMLDialogElement.prototype.showModal
const originalClose = HTMLDialogElement.prototype.close

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute('open', '')
  }

  HTMLDialogElement.prototype.close = function () {
    if (!this.hasAttribute('open')) return
    this.removeAttribute('open')
    this.dispatchEvent(new Event('close'))
  }
})

afterAll(() => {
  if (originalShowModal) HTMLDialogElement.prototype.showModal = originalShowModal
  else delete HTMLDialogElement.prototype.showModal

  if (originalClose) HTMLDialogElement.prototype.close = originalClose
  else delete HTMLDialogElement.prototype.close
})

afterEach(async () => {
  if (component) await unmount(component)
  component = null
  document.body.innerHTML = ''
})

function renderPanel() {
  const target = document.createElement('div')
  document.body.appendChild(target)

  const live = {
    handleEvent: vi.fn(),
    pushEvent: vi.fn()
  }

  component = mount(AgentMessagesPanel, {
    target,
    props: {
      activeChannelId: 7,
      messages: [{
        id: 42,
        body: 'Completed the task.\n\nTool: Bash\nmix test',
        inserted_at: '2026-09-28T12:00:00Z',
        sender_role: 'agent',
        session_id: 99,
        session_uuid: 'session-99',
        session_name: 'Implementer',
        provider: 'codex',
        attachments: [],
        reactions: []
      }],
      activeAgents: [{ id: 99, name: 'Implementer', provider: 'codex' }],
      live
    }
  })

  return { live }
}

describe('AgentMessagesPanel', () => {
  it('renders stable landmarks and labelled controls', () => {
    renderPanel()

    expect(document.querySelector('#agent-messages-panel')).not.toBeNull()
    expect(document.querySelector('#agent-messages-list[role="log"][aria-label="Channel messages"]')).not.toBeNull()
    expect(document.querySelector('#agent-message-42')).not.toBeNull()
    expect(document.querySelector('#agent-message-composer')).not.toBeNull()
    expect(document.querySelector('#agent-message-input[aria-label="Message"]')).not.toBeNull()
    expect(document.querySelector('#agent-message-42-reactions[aria-haspopup="menu"]')).not.toBeNull()
    expect(document.querySelector('#agent-message-42-actions[aria-haspopup="menu"]')).not.toBeNull()
  })

  it('opens the inspector as a labelled modal and restores focus when it closes', async () => {
    renderPanel()

    const actionsButton = document.querySelector('#agent-message-42-actions')
    actionsButton.focus()
    actionsButton.click()
    await tick()

    expect(actionsButton.getAttribute('aria-expanded')).toBe('true')
    document.querySelector('#agent-message-42-inspect').click()
    await tick()

    const dialog = document.querySelector('#agent-message-inspect-dialog')
    const closeButton = document.querySelector('#agent-message-inspect-close')

    expect(dialog).not.toBeNull()
    await vi.waitFor(() => expect(dialog.hasAttribute('open')).toBe(true))
    expect(dialog.getAttribute('aria-labelledby')).toBe('inspect-title')
    expect(document.activeElement).toBe(closeButton)

    closeButton.click()
    await tick()
    await tick()

    expect(document.querySelector('#agent-message-inspect-dialog')).toBeNull()
    expect(document.activeElement).toBe(actionsButton)
  })

  it('dismisses an open action menu with Escape', async () => {
    renderPanel()

    const actionsButton = document.querySelector('#agent-message-42-actions')
    actionsButton.click()
    await tick()

    expect(document.querySelector('#agent-message-42-actions-menu')).not.toBeNull()
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
    await tick()

    expect(document.querySelector('#agent-message-42-actions-menu')).toBeNull()
    expect(actionsButton.getAttribute('aria-expanded')).toBe('false')
  })
})
