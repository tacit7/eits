export function showToast(message) {
  const toast = document.createElement("div")
  toast.className = "fixed bottom-4 right-4 z-[9999] bg-base-content text-base-100 text-xs font-medium px-4 py-2 rounded-lg shadow-lg opacity-0 transition-opacity duration-200"
  toast.textContent = message
  document.body.appendChild(toast)
  requestAnimationFrame(() => { toast.style.opacity = "1" })
  setTimeout(() => {
    toast.style.opacity = "0"
    setTimeout(() => toast.remove(), 200)
  }, 2000)
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
