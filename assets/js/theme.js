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
