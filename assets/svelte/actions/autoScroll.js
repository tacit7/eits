/**
 * Svelte action for auto-scrolling a container to the bottom
 * Automatically scrolls when new content is added, but respects user scroll position
 *
 * Usage:
 * <div use:autoScroll={{ trigger: messages.length }}>
 *   <!-- content -->
 * </div>
 */

import { tick } from 'svelte'

export function autoScroll(node, options = {}) {
  let shouldAutoScroll = options.enabled ?? true
  let scrollThreshold = options.threshold ?? 100

  function scrollToBottom() {
    if (shouldAutoScroll) {
      node.scrollTop = node.scrollHeight
    }
  }

  function handleScroll() {
    // Check if user is near bottom
    const isAtBottom = node.scrollHeight - node.scrollTop <= node.clientHeight + scrollThreshold
    shouldAutoScroll = isAtBottom
  }

  // Attach scroll listener
  node.addEventListener('scroll', handleScroll)

  // Initial scroll after DOM updates
  tick().then(scrollToBottom)

  return {
    update(newOptions) {
      scrollThreshold = newOptions.threshold ?? scrollThreshold

      // Scroll when trigger changes (e.g., new messages added)
      if (newOptions.trigger !== options.trigger) {
        tick().then(scrollToBottom)
      }

      options = newOptions
    },

    destroy() {
      node.removeEventListener('scroll', handleScroll)
    }
  }
}
