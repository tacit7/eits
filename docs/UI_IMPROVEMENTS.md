# UI Improvements

This document tracks accessibility and usability improvements made to the EITS web UI.

## Accessibility Fixes

### 1. DM Page Textarea Scroll Fix

**Issue:** Textarea input fields with `max-height` CSS constraints prevented users from scrolling through long content, causing text to be cut off and inaccessible.

**Fix:** Added CSS `overflow-y: auto` to textarea elements that have a `max-height` constraint. This allows users to scroll within the textarea when content exceeds the maximum height, ensuring all text is accessible.

**Affected Component:** Direct message input textarea
**Files Modified:** `lib/eye_in_the_sky_web_web/components/`
**CSS Pattern:**
```css
textarea {
  max-height: <specified-height>;
  overflow-y: auto;
}
```

**Impact:** Users can now scroll through longer messages in the DM input field without losing access to content.

---

### 2. Kanban Card Accessibility Fix

**Issue:** Interactive elements (buttons, links, inputs) within Kanban cards were being caught by SortableJS drag-and-drop handler, preventing normal interaction with these elements and reducing accessibility.

**Fix:** Configured SortableJS to exclude interactive elements from drag detection via the `handle` and `ignore` options in the Kanban JS hook. This allows buttons, links, and inputs to function normally while preserving drag functionality for the card container itself.

**Affected Component:** Kanban board cards
**Files Modified:** `assets/js/hooks/kanban_hook.js`
**SortableJS Configuration:**
```javascript
new Sortable(element, {
  handle: '.drag-handle', // Only these elements trigger drag
  ignore: 'button,a,input,[contenteditable="true"]', // Exclude interactive elements
  // ... other options
});
```

**Impact:** Users can now interact with buttons, links, and form inputs on Kanban cards without accidentally triggering drag operations. This significantly improves accessibility for keyboard navigation and screen reader users.

---

## Related Documentation

- [DM_FEATURES.md](DM_FEATURES.md) - Direct messaging system
- [KANBAN.md](KANBAN.md) - Kanban board functionality
