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

export const debounce = (fn, wait = 120) => {
  let timeoutId
  const wrapped = (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn(...args), wait)
  }
  wrapped.cancel = () => clearTimeout(timeoutId)
  return wrapped
}
