import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  classifyLocalMediaHref,
  decorateLocalMediaLinks,
  installLocalMediaLinks,
} from './local_media_links'
import { renderMarkdown } from './markdown'

describe('classifyLocalMediaHref', () => {
  it.each([
    ['/Users/dev/Movies/preview.png', 'image'],
    ['/Users/dev/Movies/recovery.MOV', 'video'],
    ['/Users/dev/Movies/profiles', 'directory'],
    ['/home/dev/Videos/demo.webm', 'video'],
    ['C:\\Users\\dev\\Videos\\demo.mp4', 'video'],
  ])('classifies %s as %s', (href, kind) => {
    expect(classifyLocalMediaHref(href)).toMatchObject({ kind })
  })

  it('decodes spaces and Unicode exactly once', () => {
    expect(classifyLocalMediaHref('/Users/dev/My%20Videos/%E7%8C%AB%20clip.mp4')).toEqual({
      kind: 'video',
      path: '/Users/dev/My Videos/猫 clip.mp4',
    })
  })

  it.each([
    '/sessions/7257',
    '/projects/1/tasks',
    'https://example.com/video.mp4',
    'file:///Users/dev/video.mp4',
    '/Users/dev/notes.txt',
    '/Users/dev/%ZZ.mp4',
    '/Users/dev/video.mp4?download=1',
  ])('leaves non-local or unsafe href unchanged: %s', (href) => {
    expect(classifyLocalMediaHref(href)).toBeNull()
  })
})

describe('local media interactions', () => {
  let root

  beforeEach(() => {
    root = document.createElement('div')
    document.body.replaceChildren(root)
  })

  it('decorates only recognized local paths and provides a browser fallback', () => {
    root.innerHTML = `
      <a href="/Users/dev/My%20Videos/demo.mp4">Demo</a>
      <a href="/sessions/7257">Session</a>
      <a href="https://example.com">Website</a>
    `

    decorateLocalMediaLinks(root, false)

    expect(root.querySelectorAll('.local-media-link')).toHaveLength(1)
    expect(root.querySelectorAll('[data-local-media-action="copy"]')).toHaveLength(1)
    expect(root.querySelector('[data-local-media-action="open"]')).toBeNull()
    expect(root.querySelector('.local-media-hint').textContent).toContain('EITS Desktop')
  })

  it('recognizes the raw sanitized Markdown href without weakening sanitization', async () => {
    root.innerHTML = await renderMarkdown(
      '[Preview](/Users/dev/My%20Videos/caf%C3%A9.png) <img src="x" onerror="alert(1)">',
    )

    decorateLocalMediaLinks(root, true)

    expect(root.querySelector('.local-media-link').dataset.localMediaPath).toBe('/Users/dev/My Videos/café.png')
    expect(root.querySelector('img').hasAttribute('onerror')).toBe(false)
  })

  it('invokes native commands only after explicit user clicks', async () => {
    root.innerHTML = '<a href="/Users/dev/demo.mp4">Demo</a>'
    const invoke = vi.fn().mockResolvedValue(undefined)
    const controller = installLocalMediaLinks(root, { desktop: true, invoke })
    controller.decorate()

    expect(invoke).not.toHaveBeenCalled()
    root.querySelector('.local-media-link').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))
    root.querySelector('.local-media-link').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))
    await vi.waitFor(() => expect(invoke).toHaveBeenCalledWith('open_local_media', { path: '/Users/dev/demo.mp4' }))
    expect(invoke).toHaveBeenCalledTimes(1)

    root.querySelector('[data-local-media-action="reveal"]').click()
    await vi.waitFor(() => expect(invoke).toHaveBeenCalledWith('reveal_local_file', { path: '/Users/dev/demo.mp4' }))
  })

  it('copies paths in the browser and explains why link opening is unavailable', async () => {
    root.innerHTML = '<a href="/Users/dev/demo.png">Demo</a>'
    const copy = vi.fn().mockResolvedValue(undefined)
    const controller = installLocalMediaLinks(root, { desktop: false, copy })
    controller.decorate()

    root.querySelector('[data-local-media-action="copy"]').click()
    await vi.waitFor(() => expect(copy).toHaveBeenCalledWith('/Users/dev/demo.png'))
    expect(root.querySelector('.local-media-status').textContent).toBe('Path copied')

    root.querySelector('.local-media-link').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))
    await vi.waitFor(() => expect(root.querySelector('[role="alert"]').textContent).toContain('EITS Desktop'))
  })

  it('shows readable native errors', async () => {
    root.innerHTML = '<a href="/Users/dev/missing.mp4">Missing</a>'
    const controller = installLocalMediaLinks(root, {
      desktop: true,
      invoke: vi.fn().mockRejectedValue(new Error('File or folder does not exist')),
    })
    controller.decorate()

    root.querySelector('[data-local-media-action="open"]').click()
    await vi.waitFor(() => {
      expect(root.querySelector('[role="alert"]').textContent).toBe(
        'Could not open this item: File or folder does not exist',
      )
    })
  })

  it('does not duplicate listeners across rerenders and removes its listener on destroy', async () => {
    const invoke = vi.fn().mockResolvedValue(undefined)
    const controller = installLocalMediaLinks(root, { desktop: true, invoke })

    root.innerHTML = '<a href="/Users/dev/first.mp4">First</a>'
    controller.decorate()
    controller.decorate()
    root.querySelector('.local-media-link').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))
    await vi.waitFor(() => expect(invoke).toHaveBeenCalledTimes(1))

    root.innerHTML = '<a href="/Users/dev/second.mp4">Second</a>'
    controller.decorate()
    root.querySelector('.local-media-link').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))
    await vi.waitFor(() => expect(invoke).toHaveBeenCalledTimes(2))

    controller.destroy()
    root.querySelector('[data-local-media-action="open"]').click()
    await Promise.resolve()
    expect(invoke).toHaveBeenCalledTimes(2)
  })
})
