defmodule EyeInTheSkyWebWeb.AuthLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Accounts

  def mount(params, session, socket) do
    if session["user_id"] do
      {:ok, redirect(socket, to: "/")}
    else
      mode = if params["token"], do: :register, else: :login
      token_valid = validate_token(params["token"])

      socket =
        socket
        |> assign(:mode, mode)
        |> assign(:token, params["token"])
        |> assign(:token_valid, token_valid)
        |> assign(:error, nil)

      {:ok, socket, layout: {EyeInTheSkyWebWeb.Layouts, :root}}
    end
  end

  defp validate_token(nil), do: false

  defp validate_token(token) do
    match?({:ok, _}, Accounts.peek_registration_token(token))
  end

  def render(%{mode: :register, token_valid: false} = assigns) do
    ~H"""
    <div class="min-h-[100dvh] flex items-center justify-center bg-[oklch(95%_0.005_80)] dark:bg-[hsl(30,3.3%,11.8%)]">
      <div class="w-full max-w-sm px-6 text-center">
        <div class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-zinc-900 dark:bg-zinc-100 mb-4">
          <.icon name="hero-eye" class="w-6 h-6 text-white dark:text-zinc-900" />
        </div>
        <p class="text-sm text-red-500 dark:text-red-400 mt-2">
          This registration link is invalid or has expired.
        </p>
        <p class="text-xs text-zinc-500 dark:text-zinc-400 mt-2">
          Run
          <code class="font-mono bg-zinc-100 dark:bg-zinc-800 px-1 rounded">
            mix eits.register &lt;username&gt;
          </code>
          to get a new one.
        </p>
      </div>
    </div>
    """
  end

  def render(%{mode: :register} = assigns) do
    ~H"""
    <div class="min-h-[100dvh] flex items-center justify-center bg-[oklch(95%_0.005_80)] dark:bg-[hsl(30,3.3%,11.8%)]">
      <div class="w-full max-w-sm px-6">
        <div class="mb-8 text-center">
          <div class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-zinc-900 dark:bg-zinc-100 mb-4">
            <.icon name="hero-eye" class="w-6 h-6 text-white dark:text-zinc-900" />
          </div>
          <h1 class="text-2xl font-bold text-zinc-900 dark:text-zinc-100 font-[Bricolage_Grotesque]">
            Register Passkey
          </h1>
          <p class="text-sm text-zinc-500 dark:text-zinc-400 mt-1">Touch your passkey to register</p>
        </div>

        <div
          id="passkey-auth"
          phx-hook="PasskeyAuth"
          data-mode="register"
          data-token={@token}
          class="bg-white dark:bg-zinc-900 rounded-2xl border border-zinc-200 dark:border-zinc-800 p-6 space-y-4"
        >
          <div
            :if={@error}
            class="text-xs text-red-500 dark:text-red-400 bg-red-50 dark:bg-red-950 rounded-lg px-3 py-2"
          >
            {@error}
          </div>

          <div
            id="passkey-status"
            class="hidden text-xs text-zinc-500 dark:text-zinc-400 text-center py-1"
          >
          </div>

          <button
            id="btn-register"
            type="button"
            class="w-full px-4 py-2.5 text-sm font-medium rounded-lg bg-zinc-900 dark:bg-zinc-100 text-white dark:text-zinc-900 hover:bg-zinc-700 dark:hover:bg-zinc-300 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Register passkey
          </button>
        </div>
      </div>
    </div>
    """
  end

  def render(%{mode: :login} = assigns) do
    ~H"""
    <div class="min-h-[100dvh] flex items-center justify-center bg-[oklch(95%_0.005_80)] dark:bg-[hsl(30,3.3%,11.8%)]">
      <div class="w-full max-w-sm px-6">
        <div class="mb-8 text-center">
          <div class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-zinc-900 dark:bg-zinc-100 mb-4">
            <.icon name="hero-eye" class="w-6 h-6 text-white dark:text-zinc-900" />
          </div>
          <h1 class="text-2xl font-bold text-zinc-900 dark:text-zinc-100 font-[Bricolage_Grotesque]">
            Eye in the Sky
          </h1>
          <p class="text-sm text-zinc-500 dark:text-zinc-400 mt-1">Sign in with your passkey</p>
        </div>

        <div
          id="passkey-auth"
          phx-hook="PasskeyAuth"
          data-mode="login"
          class="bg-white dark:bg-zinc-900 rounded-2xl border border-zinc-200 dark:border-zinc-800 p-6 space-y-4"
        >
          <div>
            <label class="block text-xs font-medium text-zinc-600 dark:text-zinc-400 mb-1.5">
              Username
            </label>
            <input
              id="passkey-username"
              type="text"
              placeholder="your username"
              autocomplete="username"
              class="w-full px-3 py-2.5 text-sm rounded-lg border border-zinc-200 dark:border-zinc-700 bg-transparent text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-900 dark:focus:ring-zinc-100"
            />
          </div>

          <div
            :if={@error}
            class="text-xs text-red-500 dark:text-red-400 bg-red-50 dark:bg-red-950 rounded-lg px-3 py-2"
          >
            {@error}
          </div>

          <div
            id="passkey-status"
            class="hidden text-xs text-zinc-500 dark:text-zinc-400 text-center py-1"
          >
          </div>

          <button
            id="btn-signin"
            type="button"
            class="w-full px-4 py-2.5 text-sm font-medium rounded-lg bg-zinc-900 dark:bg-zinc-100 text-white dark:text-zinc-900 hover:bg-zinc-700 dark:hover:bg-zinc-300 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Sign in
          </button>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("auth_error", %{"message" => message}, socket) do
    {:noreply, assign(socket, :error, message)}
  end

  def handle_event("auth_success", _params, socket) do
    {:noreply, redirect(socket, to: "/")}
  end
end
