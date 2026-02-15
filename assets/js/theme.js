// Daisy UI Theme Controller Integration
// Handles theme persistence and synchronization across tabs

document.addEventListener('DOMContentLoaded', () => {
  const themeControllers = document.querySelectorAll('.theme-controller');

  // Initialize theme controllers based on current theme
  const currentTheme = document.documentElement.getAttribute('data-theme');
  themeControllers.forEach(controller => {
    if (controller.type === 'checkbox') {
      controller.checked = currentTheme === 'dark';
    }
  });

  // Listen for theme changes from Daisy UI theme controller
  themeControllers.forEach(controller => {
    controller.addEventListener('change', (e) => {
      const theme = e.target.checked ? 'dark' : 'light';
      localStorage.setItem('theme', theme);
      document.documentElement.setAttribute('data-theme', theme);

      // Sync other theme controllers on the page
      themeControllers.forEach(otherController => {
        if (otherController !== controller) {
          otherController.checked = e.target.checked;
        }
      });
    });
  });

  // Handle phx:set-theme events from LiveView theme toggle buttons
  window.addEventListener('phx:set-theme', (e) => {
    const btn = e.target.closest('[data-phx-theme]') || e.target;
    const theme = btn.getAttribute('data-phx-theme') || 'light';
    if (theme === 'system') {
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const resolvedTheme = prefersDark ? 'dark' : 'light';
      localStorage.removeItem('theme');
      document.documentElement.setAttribute('data-theme', resolvedTheme);
    } else {
      localStorage.setItem('theme', theme);
      document.documentElement.setAttribute('data-theme', theme);
    }
  });

  // Sync theme across browser tabs
  window.addEventListener('storage', (e) => {
    if (e.key === 'theme') {
      const newTheme = e.newValue || 'light';
      document.documentElement.setAttribute('data-theme', newTheme);
      themeControllers.forEach(controller => {
        controller.checked = newTheme === 'dark';
      });
    }
  });
});
