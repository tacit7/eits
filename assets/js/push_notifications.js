// Web Push notification setup for PWA (iOS 16.4+)

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const rawData = window.atob(base64)
  return Uint8Array.from([...rawData].map((c) => c.charCodeAt(0)))
}

let swRegistration = null

async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return null
  try {
    swRegistration = await navigator.serviceWorker.register("/sw.js")
    return swRegistration
  } catch (err) {
    console.error("[Push] SW registration failed:", err)
    return null
  }
}

async function getVapidPublicKey() {
  const res = await fetch("/api/v1/push/vapid-public-key")
  const data = await res.json()
  return data.public_key
}

async function subscribe() {
  if (!swRegistration) return { ok: false, reason: "no_sw" }
  if (!("PushManager" in window)) return { ok: false, reason: "no_push" }

  const permission = await Notification.requestPermission()
  if (permission !== "granted") return { ok: false, reason: "denied" }

  const publicKey = await getVapidPublicKey()

  const subscription = await swRegistration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(publicKey),
  })

  const sub = subscription.toJSON()
  const res = await fetch("/api/v1/push/subscribe", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ endpoint: sub.endpoint, keys: sub.keys }),
  })

  return res.ok ? { ok: true } : { ok: false, reason: "server_error" }
}

async function unsubscribe() {
  if (!swRegistration) return
  const sub = await swRegistration.pushManager.getSubscription()
  if (!sub) return
  await fetch("/api/v1/push/subscribe", {
    method: "DELETE",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ endpoint: sub.endpoint }),
  })
  await sub.unsubscribe()
}

async function currentPermission() {
  if (!("Notification" in window)) return "unsupported"
  return Notification.permission
}

async function isSubscribed() {
  if (!swRegistration) return false
  const sub = await swRegistration.pushManager.getSubscription()
  return !!sub
}

// Expose globally for hooks and console use
window.PushNotifications = { subscribe, unsubscribe, currentPermission, isSubscribed }

// PushSetup hook: attach to a button to enable/disable notifications
export const PushSetup = {
  async mounted() {
    // Tauri shell: WKWebView lacks service workers / PushManager. Skip the
    // Web Push path and toggle the server-side notify_on_stop flag directly —
    // the Rust side turns it into a native macOS notification.
    if (document.documentElement.dataset.env === "tauri") {
      this._setTauriState(false)
      this.el.addEventListener("click", () => {
        const enabled = this.el.dataset.pushState !== "enabled"
        this._setTauriState(enabled)
        this._notifyServer(enabled)
      })
      return
    }

    await this._sync()
    this.el.addEventListener("click", () => this._toggle())
  },
  _setTauriState(enabled) {
    const on = ["text-primary", "bg-primary/10", "hover:bg-primary/15"]
    const off = ["text-base-content/40", "hover:text-base-content/70", "hover:bg-base-content/5"]
    this.el.classList.remove(...on, ...off)
    this.el.classList.add(...(enabled ? on : off))
    this.el.title = enabled ? "Desktop notifications enabled — tap to disable" : "Enable desktop notifications"
    this.el.dataset.pushState = enabled ? "enabled" : "disabled"
  },
  async _sync() {
    const permission = await currentPermission()
    const subscribed = await isSubscribed()
    this._updateEl(permission, subscribed)
    // Sync server-side notify_on_stop with current browser state
    this._notifyServer(subscribed && permission === "granted")
  },
  async _toggle() {
    const subscribed = await isSubscribed()
    if (subscribed) {
      await unsubscribe()
      this._updateEl(await currentPermission(), false)
      this._notifyServer(false)
    } else {
      const result = await subscribe()
      this._updateEl(await currentPermission(), result.ok)
      this._notifyServer(result.ok)
    }
  },
  _notifyServer(enabled) {
    try {
      this.pushEvent("set_notify_on_stop", { enabled })
    } catch (_err) {
      // No-op: handler may not be defined in every LiveView that mounts this hook
    }
  },
  _updateEl(permission, subscribed) {
    const on = ["text-primary", "bg-primary/10", "hover:bg-primary/15"]
    const off = ["text-base-content/40", "hover:text-base-content/70", "hover:bg-base-content/5"]
    const warn = ["text-warning/70", "hover:bg-warning/10"]

    const apply = (classes) => {
      this.el.classList.remove(...on, ...off, ...warn)
      this.el.classList.add(...classes)
    }

    if (permission === "unsupported") {
      this.el.title = "Push notifications not supported"
      this.el.dataset.pushState = "unsupported"
      apply(off)
    } else if (permission === "denied") {
      this.el.title = "Notifications blocked — enable in browser settings"
      this.el.dataset.pushState = "denied"
      apply(warn)
    } else if (subscribed) {
      this.el.title = "Notifications enabled — tap to disable"
      this.el.dataset.pushState = "enabled"
      apply(on)
    } else {
      this.el.title = "Enable push notifications"
      this.el.dataset.pushState = "disabled"
      apply(off)
    }
  },
}

// Initialize SW on load
registerServiceWorker()
