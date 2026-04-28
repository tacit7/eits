export function showToast(message, type = "info") {
  const wrapper = document.createElement("div")
  wrapper.className = "toast toast-bottom toast-end z-[9999]"
  wrapper.style.opacity = "0"
  wrapper.style.transition = "opacity 0.2s"

  const alertEl = document.createElement("div")
  alertEl.className = `alert alert-${type} text-sm`
  alertEl.innerHTML = `<span>${message}</span>`

  wrapper.appendChild(alertEl)
  document.body.appendChild(wrapper)

  requestAnimationFrame(() => { wrapper.style.opacity = "1" })
  setTimeout(() => {
    wrapper.style.opacity = "0"
    setTimeout(() => wrapper.remove(), 200)
  }, 2000)
}

const SESSION_FAILURE_MESSAGES = {
  billing_error: "Billing issue — session stopped. Check usage limits.",
  authentication_error: "Authentication error — session stopped.",
  rate_limit_error: "Rate limit — session stopped after max retries.",
  retry_exhausted: "Rate limit — session stopped after max retries.",
  watchdog_timeout: "Session timed out.",
}

const SESSION_FAILURE_TOAST_LIMIT = 5
const SESSION_FAILURE_TOAST_TTL_MS = 8000

function ensureSessionFailureToastContainer() {
  let container = document.getElementById("session-failure-toast")
  if (container) return container
  container = document.createElement("div")
  container.id = "session-failure-toast"
  container.className = "toast toast-bottom toast-end z-50"
  document.body.appendChild(container)
  return container
}

export function showSessionFailureToast({ title, reason } = {}) {
  const container = ensureSessionFailureToastContainer()
  const message = SESSION_FAILURE_MESSAGES[reason] || "Session failed."

  while (container.children.length >= SESSION_FAILURE_TOAST_LIMIT) {
    container.firstElementChild?.remove()
  }

  const alertEl = document.createElement("div")
  alertEl.className = "alert alert-error text-sm shadow-lg"
  alertEl.setAttribute("role", "alert")

  const body = document.createElement("div")
  body.className = "flex flex-col gap-0.5"

  if (title) {
    const titleEl = document.createElement("span")
    titleEl.className = "font-semibold"
    titleEl.textContent = title
    body.appendChild(titleEl)
  }

  const messageEl = document.createElement("span")
  messageEl.textContent = message
  body.appendChild(messageEl)

  alertEl.appendChild(body)
  container.appendChild(alertEl)

  setTimeout(() => alertEl.remove(), SESSION_FAILURE_TOAST_TTL_MS)
}

export const debounce = (fn, wait = 120) => {
  let timeoutId
  const wrapped = (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn(...args), wait)
  }
  wrapped.cancel = () => clearTimeout(timeoutId)
  return wrapped
}
