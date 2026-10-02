const IMAGE_EXTENSIONS = new Set([
  'avif', 'bmp', 'gif', 'heic', 'heif', 'jpeg', 'jpg', 'png', 'tif', 'tiff', 'webp',
])

const VIDEO_EXTENSIONS = new Set([
  'avi', 'm4v', 'mkv', 'mov', 'mp4', 'mpeg', 'mpg', 'webm',
])

// A leading slash alone is ambiguous in EITS: `/sessions/7257` is an app route.
// Directory candidates therefore need a recognizable local filesystem root,
// while Windows paths need an absolute drive prefix.
const POSIX_LOCAL_ROOT = /^\/(?:Users|home|Volumes|mnt|media|private|tmp)(?:\/|$)/
const WINDOWS_ABSOLUTE_PATH = /^[A-Za-z]:[\\/]/

function decodeLocalPath(rawHref) {
  if (typeof rawHref !== 'string' || rawHref.length === 0) return null
  if (rawHref.includes('\0') || /%(?![0-9a-f]{2})/i.test(rawHref)) return null
  if (rawHref.includes('?') || rawHref.includes('#')) return null

  try {
    const decoded = decodeURIComponent(rawHref)
    if (decoded.includes('\0')) return null
    return decoded
  } catch (_error) {
    return null
  }
}

/**
 * Classify a raw (unresolved) anchor href as a supported local media target.
 * Returns null for web URLs, EITS routes, unsupported files, and malformed input.
 */
export function classifyLocalMediaHref(rawHref) {
  const path = decodeLocalPath(rawHref)
  if (!path) return null

  const windowsPath = WINDOWS_ABSOLUTE_PATH.test(path)
  const posixPath = POSIX_LOCAL_ROOT.test(path)
  if (!windowsPath && !posixPath) return null

  const normalized = path.replace(/\\/g, '/')
  const basename = normalized.replace(/\/+$/, '').split('/').at(-1) ?? ''
  const dotIndex = basename.lastIndexOf('.')
  const extension = dotIndex > 0 ? basename.slice(dotIndex + 1).toLowerCase() : ''

  if (IMAGE_EXTENSIONS.has(extension)) return { kind: 'image', path }
  if (VIDEO_EXTENSIONS.has(extension)) return { kind: 'video', path }
  if (extension || basename.startsWith('.')) return null

  return { kind: 'directory', path }
}

function actionButton(action, label) {
  const button = document.createElement('button')
  button.type = 'button'
  button.className = 'local-media-action'
  button.dataset.localMediaAction = action
  button.textContent = label
  return button
}

function decorateLink(link, media, desktop) {
  link.classList.add('local-media-link')
  link.dataset.localMediaPath = media.path
  link.dataset.localMediaKind = media.kind
  link.title = desktop ? 'Open with the default application' : 'Opening local files requires EITS Desktop'

  const actions = document.createElement('span')
  actions.className = 'local-media-actions'
  actions.dataset.localMediaPath = media.path

  if (desktop) {
    actions.append(
      actionButton('open', 'Open externally'),
      actionButton('reveal', 'Show in Finder'),
    )
  }
  actions.append(actionButton('copy', 'Copy path'))

  if (!desktop) {
    const hint = document.createElement('span')
    hint.className = 'local-media-hint'
    hint.textContent = 'EITS Desktop required to open'
    actions.append(hint)
  }

  const status = document.createElement('span')
  status.className = 'local-media-status'
  status.setAttribute('role', 'status')
  status.setAttribute('aria-live', 'polite')
  actions.append(status)

  link.insertAdjacentElement('afterend', actions)
}

/** Add actions to newly rendered Markdown without registering any listeners. */
export function decorateLocalMediaLinks(root, desktop = Boolean(window.__TAURI_INTERNALS__)) {
  root.querySelectorAll('a[href]').forEach((link) => {
    if (link.classList.contains('local-media-link')) return
    const media = classifyLocalMediaHref(link.getAttribute('href'))
    if (media) decorateLink(link, media, desktop)
  })
}

function statusFor(actionElement) {
  let actions = actionElement.closest('.local-media-actions')
  if (!actions && actionElement.nextElementSibling?.matches('.local-media-actions')) {
    actions = actionElement.nextElementSibling
  }
  return actions?.querySelector('.local-media-status') ?? null
}

function setStatus(actionElement, message, error = false) {
  const status = statusFor(actionElement)
  if (!status) return
  status.textContent = message
  status.classList.toggle('local-media-status--error', error)
  status.setAttribute('role', error ? 'alert' : 'status')
}

function errorMessage(error, fallback) {
  const message = typeof error === 'string' ? error : error?.message
  return message ? `${fallback}: ${message}` : fallback
}

/**
 * Install one delegated listener for the hook lifetime. Calling decorate()
 * after a LiveView rerender is safe and does not duplicate the listener.
 */
export function installLocalMediaLinks(root, options = {}) {
  const desktop = options.desktop ?? Boolean(window.__TAURI_INTERNALS__)
  const invoke = options.invoke ?? ((command, args) => window.__TAURI_INTERNALS__.invoke(command, args))
  const copy = options.copy ?? ((text) => desktop
    ? invoke('plugin:clipboard-manager|write_text', { text })
    : navigator.clipboard.writeText(text))

  const onClick = async (event) => {
    const element = event.target.closest?.('[data-local-media-action], a.local-media-link')
    if (!element || !root.contains(element)) return

    const link = element.matches('a.local-media-link') ? element : null
    const action = link ? 'open' : element.dataset.localMediaAction
    const path = link?.dataset.localMediaPath || element.closest('.local-media-actions')?.dataset.localMediaPath
    if (!action || !path) return

    event.preventDefault()
    event.stopPropagation()
    if (element.getAttribute('aria-busy') === 'true') return

    if (action === 'copy') {
      try {
        await copy(path)
        setStatus(element, 'Path copied')
      } catch (error) {
        setStatus(element, errorMessage(error, 'Could not copy path'), true)
      }
      return
    }

    if (!desktop) {
      setStatus(element, 'Opening local files requires EITS Desktop', true)
      return
    }

    element.setAttribute('aria-busy', 'true')
    if (element instanceof HTMLButtonElement) element.disabled = true
    try {
      const command = action === 'reveal' ? 'reveal_local_file' : 'open_local_media'
      await invoke(command, { path })
      setStatus(element, action === 'reveal' ? 'Shown in Finder' : 'Opened externally')
    } catch (error) {
      const fallback = action === 'reveal' ? 'Could not show this item' : 'Could not open this item'
      setStatus(element, errorMessage(error, fallback), true)
    } finally {
      element.removeAttribute('aria-busy')
      if (element instanceof HTMLButtonElement) element.disabled = false
    }
  }

  root.addEventListener('click', onClick)

  return {
    decorate() {
      decorateLocalMediaLinks(root, desktop)
    },
    destroy() {
      root.removeEventListener('click', onClick)
    },
  }
}
