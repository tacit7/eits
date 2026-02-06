defmodule EyeInTheSkyWebWeb.ThemeLive do
  use EyeInTheSkyWebWeb, :live_view

  @themes [
    "abyss",
    "acid",
    "aqua",
    "autumn",
    "black",
    "bumblebee",
    "business",
    "caramellatte",
    "cmyk",
    "coffee",
    "corporate",
    "cupcake",
    "cyberpunk",
    "dark",
    "dim",
    "dracula",
    "emerald",
    "fantasy",
    "forest",
    "garden",
    "halloween",
    "lemonade",
    "light",
    "lofi",
    "luxury",
    "night",
    "nord",
    "pastel",
    "retro",
    "silk",
    "sunset",
    "synthwave",
    "valentine",
    "winter",
    "wireframe"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Themes")
     |> assign(:themes, @themes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <h1 class="text-3xl font-bold text-base-content mb-2">Themes</h1>
        <p class="text-base-content/60 mb-8">
          Select a theme to preview and apply it to your interface. Click on any theme card to see it in action.
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <%= for theme <- @themes do %>
            <div
              class="card bg-base-100 shadow-md hover:shadow-lg transition-shadow cursor-pointer border border-base-300 hover:border-primary"
              phx-click="set_theme"
              phx-value-theme={theme}
            >
              <div class="card-body p-4">
                <!-- Theme Preview -->
                <div
                  class="rounded-lg p-4 mb-3"
                  data-theme={theme}
                  style="background-color: hsl(var(--b1)); color: hsl(var(--bc));"
                >
                  <div class="text-sm font-semibold mb-2">{theme}</div>
                  <div class="flex gap-2 flex-wrap">
                    <div
                      class="w-6 h-6 rounded"
                      style="background-color: hsl(var(--p));"
                      title="Primary"
                    />
                    <div
                      class="w-6 h-6 rounded"
                      style="background-color: hsl(var(--s));"
                      title="Secondary"
                    />
                    <div
                      class="w-6 h-6 rounded"
                      style="background-color: hsl(var(--a));"
                      title="Accent"
                    />
                    <div
                      class="w-6 h-6 rounded"
                      style="background-color: hsl(var(--su));"
                      title="Success"
                    />
                    <div
                      class="w-6 h-6 rounded"
                      style="background-color: hsl(var(--wa));"
                      title="Warning"
                    />
                    <div
                      class="w-6 h-6 rounded"
                      style="background-color: hsl(var(--er));"
                      title="Error"
                    />
                  </div>
                </div>
                
    <!-- Theme Name -->
                <h3 class="card-title text-sm capitalize">{theme}</h3>
                
    <!-- Apply Button -->
                <div class="card-actions">
                  <button
                    class="btn btn-sm btn-primary w-full"
                    onclick={"setTheme('#{theme}')"}
                  >
                    Apply
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <script>
      function setTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('theme', theme);
      }
    </script>
    """
  end

  @impl true
  def handle_event("set_theme", %{"theme" => _theme}, socket) do
    {:noreply, socket}
  end
end
