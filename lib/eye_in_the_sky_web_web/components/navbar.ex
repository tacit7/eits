defmodule EyeInTheSkyWebWeb.Components.Navbar do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.Projects
  import EyeInTheSkyWebWeb.Components.Icons

  @impl true
  def mount(socket) do
    projects = Projects.list_projects()
    {:ok, assign(socket, projects: projects, current_project: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="navbar bg-base-100 shadow-sm">
        <div class="navbar-start">
          <a href="/" class="btn btn-ghost text-xl">
            <img src="/images/logo.svg" width="36" /> Eye in the Sky
          </a>
        </div>
        <div class="navbar-center hidden lg:flex">
          <ul class="menu menu-horizontal px-1">
            <li><a href="/">Overview</a></li>
            <li><a href="/prompts">Prompts</a></li>
            <li><a href="/chat">Chat</a></li>
            <li><a href="/nats">NATS</a></li>
          </ul>
        </div>
        <div class="navbar-end gap-2">
          <div class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-circle">
              <.adjustments_horizontal class="w-6 h-6" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow"
            >
              <li><a href="/settings">Settings</a></li>
              <li>
                <button class="flex items-center justify-between" onclick="toggleDarkMode()">
                  <span>Dark Mode</span>
                  <span id="theme-toggle-icon" class="text-lg">🌙</span>
                </button>
              </li>
            </ul>
          </div>
          <EyeInTheSkyWebWeb.Layouts.project_switcher
            projects={@projects}
            current_project={@current_project}
          />
        </div>
      </div>

      <script>
        const darkThemes = new Set([
          'abyss', 'black', 'business', 'cyberpunk', 'dark', 'dim', 'dracula',
          'forest', 'halloween', 'luxury', 'night', 'nord', 'synthwave'
        ]);

        const lightThemes = new Set([
          'acid', 'aqua', 'autumn', 'bumblebee', 'caramellatte', 'cmyk',
          'coffee', 'corporate', 'cupcake', 'emerald', 'fantasy', 'garden',
          'lemonade', 'light', 'lofi', 'pastel', 'retro', 'silk', 'sunset',
          'valentine', 'winter', 'wireframe'
        ]);

        function isDarkTheme(theme) {
          return darkThemes.has(theme);
        }

        function setTheme(theme) {
          if (theme === 'system') {
            const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            document.documentElement.setAttribute('data-theme', systemTheme);
            localStorage.setItem('theme', 'system');
          } else {
            document.documentElement.setAttribute('data-theme', theme);
            localStorage.setItem('theme', theme);
          }
          updateThemeIcon();
        }

        function updateThemeIcon() {
          const currentTheme = document.documentElement.getAttribute('data-theme');
          const icon = document.getElementById('theme-toggle-icon');
          if (!icon) return;
          icon.textContent = isDarkTheme(currentTheme) ? '🌙' : '☀️';
        }

        function toggleDarkMode() {
          const html = document.documentElement;
          const currentTheme = html.getAttribute('data-theme');
          const isDark = isDarkTheme(currentTheme);
          const newTheme = isDark ? 'light' : 'dark';

          html.setAttribute('data-theme', newTheme);
          localStorage.setItem('theme', newTheme);

          const icon = document.getElementById('theme-toggle-icon');
          icon.textContent = newTheme === 'dark' ? '🌙' : '☀️';
        }

        // Initialize icon and watch for theme changes
        window.addEventListener('load', function() {
          updateThemeIcon();
        });

        // Watch for theme changes via MutationObserver
        const observer = new MutationObserver(function() {
          updateThemeIcon();
        });

        observer.observe(document.documentElement, {
          attributes: true,
          attributeFilter: ['data-theme']
        });
      </script>
    </div>
    """
  end
end
