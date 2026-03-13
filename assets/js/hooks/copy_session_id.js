export const CopySessionId = {
  mounted() {
    this.handleClick = (e) => {
      e.stopPropagation(); // Prevent row click navigation

      const sessionId = this.el.dataset.sessionId;
      if (!sessionId) return;

      // Copy to clipboard
      if (navigator.clipboard?.writeText) {
        navigator.clipboard
          .writeText(sessionId)
          .then(() => {
            this.showTooltip("Copied!");
          })
          .catch((_err) => {
            this.showTooltip("Copy failed");
          });
      } else {
        // Fallback for browsers without clipboard API
        this.showTooltip("Copy not supported");
      }
    };

    this.el.addEventListener("click", this.handleClick);
  },

  showTooltip(message) {
    // Create tooltip element
    const tooltip = document.createElement("div");
    tooltip.textContent = message;
    tooltip.className = "absolute -top-8 left-1/2 -translate-x-1/2 bg-gray-900 dark:bg-gray-700 text-white text-xs px-2 py-1 rounded whitespace-nowrap z-50 pointer-events-none";

    // Position relative to button
    this.el.style.position = "relative";
    this.el.appendChild(tooltip);

    // Remove after 2 seconds
    setTimeout(() => {
      tooltip.remove();
    }, 2000);
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener("click", this.handleClick);
    }
  }
};
