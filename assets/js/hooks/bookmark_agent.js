const MAX_BOOKMARKS = 4;
const STORAGE_KEY = 'eye-in-the-sky-bookmarks';

export const BookmarkAgent = {
  mounted() {
    this.agentId = this.el.dataset.agentId;
    this.sessionId = this.el.dataset.sessionId;
    this.agentName = this.el.dataset.agentName;
    this.agentStatus = this.el.dataset.agentStatus;

    // Update UI based on bookmark state
    this.updateBookmarkUI();

    // Handle click
    this.el.addEventListener('click', (e) => {
      e.stopPropagation();
      this.toggleBookmark();
    });
  },

  updated() {
    this.agentId = this.el.dataset.agentId;
    this.sessionId = this.el.dataset.sessionId;
    this.agentName = this.el.dataset.agentName;
    this.agentStatus = this.el.dataset.agentStatus;
    this.updateBookmarkUI();
  },

  toggleBookmark() {
    const bookmarks = this.getBookmarks();
    const index = bookmarks.findIndex(b => b.session_id === this.sessionId);

    if (index >= 0) {
      // Remove bookmark
      bookmarks.splice(index, 1);
      this.saveBookmarks(bookmarks);
      this.showToast('Bookmark removed', 'info');
    } else {
      // Add bookmark
      if (bookmarks.length >= MAX_BOOKMARKS) {
        this.showToast(`Maximum ${MAX_BOOKMARKS} bookmarks allowed`, 'error');
        return;
      }

      bookmarks.push({
        agent_id: this.agentId,
        session_id: this.sessionId,
        name: this.agentName,
        status: this.agentStatus
      });

      this.saveBookmarks(bookmarks);
      this.showToast('Agent bookmarked', 'success');
    }

    this.updateBookmarkUI();

    // Notify other components
    window.dispatchEvent(new CustomEvent('bookmarks-updated', {
      detail: { bookmarks: this.getBookmarks() }
    }));
  },

  getBookmarks() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      return stored ? JSON.parse(stored) : [];
    } catch (_e) {
      return [];
    }
  },

  saveBookmarks(bookmarks) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(bookmarks));
    } catch (_e) {
    }
  },

  updateBookmarkUI() {
    const bookmarks = this.getBookmarks();
    const isBookmarked = bookmarks.some(b => b.session_id === this.sessionId);

    // Update icon and color
    if (isBookmarked) {
      this.el.classList.remove('text-base-content/40');
      this.el.classList.add('text-warning');
      // Use filled heart icon
      const icon = this.el.querySelector('.bookmark-icon');
      if (icon) {
        icon.innerHTML = '<path d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" />';
      }
    } else {
      this.el.classList.remove('text-warning');
      this.el.classList.add('text-base-content/40');
      // Use outline heart icon
      const icon = this.el.querySelector('.bookmark-icon');
      if (icon) {
        icon.innerHTML = '<path fill-rule="evenodd" d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" clip-rule="evenodd" />';
        icon.style.fill = isBookmarked ? 'currentColor' : 'none';
        icon.style.stroke = isBookmarked ? 'none' : 'currentColor';
      }
    }
  },

  showToast(message, type = 'info') {
    // Create toast notification
    const toast = document.createElement('div');
    toast.className = `alert alert-${type} fixed bottom-24 right-4 w-auto max-w-sm shadow-lg z-50 transition-opacity`;
    toast.textContent = message;

    document.body.appendChild(toast);

    // Fade out and remove after 2 seconds
    setTimeout(() => {
      toast.style.opacity = '0';
      setTimeout(() => {
        document.body.removeChild(toast);
      }, 300);
    }, 2000);
  }
};
