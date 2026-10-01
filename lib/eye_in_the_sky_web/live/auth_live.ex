defmodule EyeInTheSkyWeb.AuthLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Accounts

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

      {:ok, socket, layout: false}
    end
  end

  defp validate_token(nil), do: false

  defp validate_token(token) do
    match?({:ok, _}, Accounts.peek_registration_token(token))
  end

  def render(%{mode: :register, token_valid: false} = assigns) do
    ~H"""
    <div class="min-h-[100dvh] flex items-center justify-center bg-base-100">
      <div class="w-full max-w-sm px-6 text-center">
        <div class="inline-flex items-center justify-center w-12 h-12 rounded-box bg-primary mb-4">
          <.icon name="hero-eye" class="size-6 text-primary-content" />
        </div>
        <p class="text-message text-error mt-2">
          This registration link is invalid or has expired.
        </p>
        <p class="text-mini text-base-content/50 mt-2">
          Run
          <code class="font-mono bg-base-200 text-base-content px-1 rounded-box">
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
    <div class="min-h-[100dvh] flex items-center justify-center bg-base-100">
      <div class="w-full max-w-sm px-6">
        <div class="mb-8 text-center">
          <div class="inline-flex items-center justify-center w-12 h-12 rounded-box bg-primary mb-4">
            <.icon name="hero-eye" class="size-6 text-primary-content" />
          </div>
          <h1 class="text-2xl font-bold text-base-content font-[Bricolage_Grotesque]">
            Register Passkey
          </h1>
          <p class="text-message text-base-content/50 mt-1">Touch your passkey to register</p>
        </div>

        <div
          id="passkey-auth"
          phx-hook="PasskeyAuth"
          data-mode="register"
          data-token={@token}
          class="bg-base-200 rounded-box border border-base-content/10 p-6 space-y-4"
        >
          <div
            :if={@error}
            class="text-mini text-error bg-error/10 rounded-box px-3 py-2"
          >
            {@error}
          </div>

          <div
            id="passkey-status"
            class="hidden text-mini text-base-content/50 text-center py-1"
          >
          </div>

          <button
            id="btn-register"
            type="button"
            class="w-full px-4 py-2.5 text-message font-medium rounded-box bg-primary text-primary-content hover:bg-primary/85 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
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
    <div class="min-h-[100dvh] flex items-center justify-center bg-base-100">
      <div class="w-full max-w-sm px-6">
        <div class="mb-8 text-center">
          <div class="inline-flex items-center justify-center w-12 h-12 rounded-box bg-primary mb-4">
            <.icon name="hero-eye" class="size-6 text-primary-content" />
          </div>
          <h1 class="text-2xl font-bold text-base-content font-[Bricolage_Grotesque]">
            Eye in the Sky
          </h1>
          <p class="text-message text-base-content/50 mt-1">Sign in with your passkey</p>
        </div>

        <div
          id="passkey-auth"
          phx-hook="PasskeyAuth"
          data-mode="login"
          class="bg-base-200 rounded-box border border-base-content/10 p-6 space-y-4"
        >
          <div>
            <label class="block text-mini font-medium text-base-content/60 mb-1.5">
              Username
            </label>
            <input
              id="passkey-username"
              type="text"
              placeholder="your username"
              autocomplete="username"
              class="w-full px-3 py-2.5 text-message rounded-box border border-base-content/15 bg-base-100 text-base-content placeholder:text-base-content/35 focus:outline-none focus:ring-2 focus:ring-primary"
            />
          </div>

          <div
            :if={@error}
            class="text-mini text-error bg-error/10 rounded-box px-3 py-2"
          >
            {@error}
          </div>

          <div
            id="passkey-status"
            class="hidden text-mini text-base-content/50 text-center py-1"
          >
          </div>

          <button
            id="btn-signin"
            type="button"
            class="w-full px-4 py-2.5 text-message font-medium rounded-box bg-primary text-primary-content hover:bg-primary/85 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
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
