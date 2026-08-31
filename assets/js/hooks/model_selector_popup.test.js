import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { ModelSelectorPopup } from './model_selector_popup.js'

function makeSelector(models) {
  document.body.innerHTML = `
    <div
      id="model-selector"
      data-event="model_and_provider_selected"
      data-selected-provider="claude"
      data-selected-model="claude-sonnet-4-6"
      data-models='${JSON.stringify(models)}'
    >
      <button type="button" data-selector-trigger>Model</button>
      <div data-selector-popover class="hidden">
        <input type="text" data-selector-search />
        <ul data-selector-list></ul>
      </div>
    </div>
  `

  const hook = Object.create(ModelSelectorPopup)
  hook.el = document.querySelector('#model-selector')
  hook.pushEventTo = vi.fn()
  hook.mounted()
  return hook
}

describe('ModelSelectorPopup', () => {
  beforeEach(() => {
    HTMLElement.prototype.scrollIntoView = vi.fn()
  })

  afterEach(() => {
    document.body.innerHTML = ''
    vi.restoreAllMocks()
  })

  it('expands hidden provider models without scrolling the viewport', () => {
    const hook = makeSelector([
      {
        provider: 'claude',
        slug: 'claude-sonnet-4-6',
        label: 'Sonnet 4.6',
        group: 'Claude Code',
        legacy: false,
        premium: false,
        default: true,
      },
      {
        provider: 'codex',
        slug: 'gpt-5.6-sol',
        label: 'GPT-5.6 Sol',
        group: 'Codex',
        legacy: false,
        premium: false,
        default: true,
      },
      {
        provider: 'codex',
        slug: 'gpt-5.6-codex',
        label: 'GPT-5.6 Codex',
        group: 'Codex',
        legacy: true,
        premium: false,
        default: false,
      },
    ])

    hook._openPopover()
    HTMLElement.prototype.scrollIntoView.mockClear()

    const disclosure = hook._list.querySelector('[data-disclosure-toggle="Codex"]')
    disclosure.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }))

    expect(hook._list.querySelector('[data-slug="gpt-5.6-codex"]')).not.toBeNull()
    expect(HTMLElement.prototype.scrollIntoView).not.toHaveBeenCalled()

    hook.destroyed()
  })
})
