// PasskeyAuth LiveView hook — handles WebAuthn registration and authentication
// Uses the browser's native WebAuthn API (navigator.credentials)

function b64url(buffer) {
  const bytes = new Uint8Array(buffer)
  let str = ""
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")
}

function fromB64url(str) {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/")
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function showStatus(el, msg) {
  const status = el.querySelector("#passkey-status")
  if (status) {
    status.textContent = msg
    status.classList.remove("hidden")
  }
}

function setDisabled(el, disabled) {
  el.querySelectorAll("button").forEach(b => b.disabled = disabled)
}

async function jsonPost(url, body) {
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: JSON.stringify(body)
  })
  const data = await resp.json()
  if (!resp.ok) throw new Error(data.error || `Request failed: ${resp.status}`)
  return data
}

export const PasskeyAuth = {
  mounted() {
    const mode = this.el.dataset.mode
    if (mode === "register") {
      this.el.querySelector("#btn-register")?.addEventListener("click", () => this._register())
    } else {
      this.el.querySelector("#btn-signin")?.addEventListener("click", () => this._login())
    }
  },

  async _register() {
    const el = this.el
    const token = el.dataset.token

    setDisabled(el, true)
    showStatus(el, "Requesting registration challenge...")

    try {
      const opts = await jsonPost("/auth/register/challenge", { token })

      opts.challenge = fromB64url(opts.challenge)
      opts.user.id = fromB64url(opts.user.id)
      if (opts.excludeCredentials) {
        opts.excludeCredentials = opts.excludeCredentials.map(c => ({ ...c, id: fromB64url(c.id) }))
      }

      showStatus(el, "Touch your passkey...")
      const cred = await navigator.credentials.create({ publicKey: opts })

      showStatus(el, "Verifying...")
      await jsonPost("/auth/register/complete", {
        id: b64url(cred.rawId),
        attestationObject: b64url(cred.response.attestationObject),
        clientDataJSON: b64url(cred.response.clientDataJSON),
        type: cred.type
      })

      showStatus(el, "Registered! Redirecting...")
      this.pushEvent("auth_success", {})
    } catch (err) {
      setDisabled(el, false)
      this.pushEvent("auth_error", { message: err.message || "Registration failed" })
    }
  },

  async _login() {
    const el = this.el
    const username = el.querySelector("#passkey-username")?.value.trim()
    if (!username) {
      this.pushEvent("auth_error", { message: "Enter your username" })
      return
    }

    setDisabled(el, true)
    showStatus(el, "Requesting authentication challenge...")

    try {
      const opts = await jsonPost("/auth/login/challenge", { username })

      opts.challenge = fromB64url(opts.challenge)
      if (opts.allowCredentials) {
        opts.allowCredentials = opts.allowCredentials.map(c => ({ ...c, id: fromB64url(c.id) }))
      }

      showStatus(el, "Touch your passkey...")
      const assertion = await navigator.credentials.get({ publicKey: opts })

      showStatus(el, "Verifying...")
      await jsonPost("/auth/login/complete", {
        id: b64url(assertion.rawId),
        authenticatorData: b64url(assertion.response.authenticatorData),
        clientDataJSON: b64url(assertion.response.clientDataJSON),
        signature: b64url(assertion.response.signature),
        userHandle: assertion.response.userHandle ? b64url(assertion.response.userHandle) : null,
        type: assertion.type
      })

      showStatus(el, "Authenticated! Redirecting...")
      this.pushEvent("auth_success", {})
    } catch (err) {
      setDisabled(el, false)
      this.pushEvent("auth_error", { message: err.message || "Authentication failed" })
    }
  }
}
