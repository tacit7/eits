import { TOUCH_DEVICE } from "./touch_gesture"
import { showToast } from "./utils"

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
      showToast('Bookmark removed', 'info');
    } else {
      // Add bookmark
      if (bookmarks.length >= MAX_BOOKMARKS) {
        showToast(`Maximum ${MAX_BOOKMARKS} bookmarks allowed`, 'error');
        return;
      }

      bookmarks.push({
        agent_id: this.agentId,
        session_id: this.sessionId,
        name: this.agentName,
        status: this.agentStatus
      });

      this.saveBookmarks(bookmarks);
      showToast('Agent bookmarked', 'success');
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
    const icon = this.el.querySelector('.bookmark-icon');

    // Swipe panel fav button: hide heart when not bookmarked, filled red when bookmarked
    if (this.el.dataset.swipeFav) {
      if (isBookmarked) {
        if (icon) {
          icon.style.opacity = '1';
          icon.style.fill = 'currentColor';
          icon.style.stroke = 'none';
          icon.innerHTML = '<path d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" />';
        }
      } else {
        if (icon) icon.style.opacity = '0';
      }
      return;
    }

    // Standard bookmark button (sidebar / actions slot)
    if (isBookmarked) {
      this.el.classList.remove('text-base-content/40');
      this.el.classList.add('text-warning');
      if (icon) {
        icon.style.opacity = '1';
        icon.style.fill = 'currentColor';
        icon.style.stroke = 'none';
        icon.innerHTML = '<path d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" />';
      }
    } else {
      this.el.classList.remove('text-warning');
      this.el.classList.add('text-base-content/40');
      if (icon) {
        if (TOUCH_DEVICE) {
          // On mobile: hide heart entirely — swipe panel is how you bookmark
          icon.style.opacity = '0';
        } else {
          icon.style.opacity = '1';
          icon.style.fill = 'none';
          icon.style.stroke = 'currentColor';
          icon.innerHTML = '<path fill-rule="evenodd" d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" clip-rule="evenodd" />';
        }
      }
    }
  },

};
