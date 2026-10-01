import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { projectCommands } from './projects.js'
import { navigationCommands } from './navigation.js'
import { CommandPalette } from '../command_palette.js'

describe('project palette commands', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('marks Switch Project results as rail project selections', async () => {
    const hook = {
      pushEvent: vi.fn(() => {
        hook._paletteProjectsResolve([{ id: 11, name: 'urielm' }])
      }),
    }

    const [submenu] = projectCommands(hook)
    const [command] = await submenu.commands()

    expect(command).toMatchObject({
      href: '/projects/11/sessions',
      railProjectId: 11,
    })
  })

  it('marks Go to Project results as rail project selections', () => {
    const hook = {
      el: {
        dataset: {
          projects: JSON.stringify([{ id: 11, name: 'urielm' }]),
        },
      },
    }

    const submenu = navigationCommands(hook).find(command => command.id === 'go-project')
    const [command] = submenu.commands()

    expect(command).toMatchObject({
      href: '/projects/11',
      railProjectId: 11,
    })
  })

  it('persists the selected rail project before navigating', async () => {
    const assign = vi.fn()
    vi.stubGlobal('location', { assign })
    localStorage.setItem('rail_state', JSON.stringify({ version: 1, section: 'sessions', project_id: 1 }))

    const el = document.createElement('dialog')
    el.close = vi.fn()

    const hook = Object.create(CommandPalette)
    hook.el = el
    hook.saveRecent = vi.fn()

    await hook.activate({
      id: 'go-project-11',
      label: 'urielm',
      type: 'navigate',
      href: '/projects/11',
      railProjectId: 11,
    })

    expect(JSON.parse(localStorage.getItem('rail_state'))).toMatchObject({
      version: 1,
      section: 'sessions',
      project_id: 11,
    })
    expect(assign).toHaveBeenCalledWith('/projects/11')
  })
})
