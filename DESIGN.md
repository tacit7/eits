---
name: "Eye in the Sky"
description: "A compact operator console for coordinating AI coding agents, tasks, sessions, direct messages, commits, jobs, and intervention points."
colors:
  warm_rail: "hsl(30 3.3% 10%)"
  warm_flyout: "hsl(30 3.3% 11.8%)"
  warm_canvas: "hsl(60 2.7% 14.5%)"
  warm_card: "hsl(60 2.1% 18.4%)"
  warm_card_hover: "hsl(60 2.1% 21%)"
  warm_tool: "hsl(50 2.5% 16%)"
  warm_selected: "hsl(15 35% 21%)"
  warm_text: "hsl(48 33.3% 97.1%)"
  warm_text_muted: "hsl(48 8% 64%)"
  warm_accent: "hsl(15 63.1% 59.6%)"
  warm_success: "hsl(97 59.1% 46.1%)"
  warm_warning: "hsl(40 71% 50%)"
  warm_error: "hsl(0 67% 59.6%)"
  warm_info: "hsl(210 65.5% 67.1%)"
  pampas_canvas: "oklch(97.5% 0.004 85)"
  pampas_panel: "oklch(94.5% 0.006 85)"
  pampas_card: "oklch(96% 0.006 85)"
  pampas_border: "oklch(91% 0.012 90)"
  pampas_text: "oklch(12% 0.008 100)"
  pampas_accent: "oklch(61% 0.15 42)"
  tokyo_canvas: "#1a1a22"
  tokyo_card: "#1e1e27"
  tokyo_border: "#25253a"
  tokyo_text: "#cdd6f4"
  tokyo_text_muted: "#6c7086"
  tokyo_accent: "#7aa2f7"
  tokyo_success: "#9ece6a"
  tokyo_warning: "#e0af68"
  tokyo_error: "#f7768e"
typography:
  title:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "normal"
  body:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "normal"
  label:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "0.6875rem"
    fontWeight: 600
    lineHeight: 1.35
    letterSpacing: "0.02em"
  metadata:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
    fontSize: "0.6875rem"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "normal"
rounded:
  selector: "0.25rem"
  field: "0.5rem"
  box: "0.5rem"
  menu: "8px"
  active_strip: "0 2px 2px 0"
spacing:
  xxs: "0.25rem"
  xs: "0.375rem"
  sm: "0.5rem"
  md: "0.75rem"
  lg: "1rem"
  xl: "1.5rem"
components:
  primary_button:
    backgroundColor: "{colors.warm_accent}"
    textColor: "#ffffff"
    borderColor: "transparent"
    rounded: "{rounded.field}"
    height: "1.75rem"
    padding: "0.375rem 0.625rem"
    font: "{typography.label}"
  ghost_icon_button:
    backgroundColor: "transparent"
    textColor: "{colors.warm_text_muted}"
    borderColor: "transparent"
    rounded: "{rounded.selector}"
    size: "1.75rem"
    hoverBackgroundColor: "{colors.warm_card_hover}"
  rail_flyout:
    backgroundColor: "{colors.warm_flyout}"
    borderColor: "color-mix(in oklab, currentColor 10%, transparent)"
    width: "236px"
    rounded: "0"
  session_row:
    backgroundColor: "transparent"
    selectedBackgroundColor: "color-mix(in oklab, {colors.warm_accent} 8%, transparent)"
    selectedBorderColor: "color-mix(in oklab, {colors.warm_accent} 20%, transparent)"
    rounded: "{rounded.box}"
    padding: "0.75rem"
  square_checkbox:
    backgroundColor: "transparent"
    checkedBackgroundColor: "{colors.warm_accent}"
    borderColor: "color-mix(in oklab, currentColor 20%, transparent)"
    rounded: "{rounded.selector}"
    size: "1rem"
  search_input:
    backgroundColor: "{colors.warm_tool}"
    textColor: "{colors.warm_text}"
    borderColor: "color-mix(in oklab, currentColor 10%, transparent)"
    rounded: "{rounded.field}"
    height: "1.75rem"
  context_menu:
    backgroundColor: "#161619"
    textColor: "{colors.warm_text}"
    borderColor: "rgba(255,255,255,0.10)"
    rounded: "{rounded.menu}"
    shadow: "0 10px 38px rgba(0, 0, 0, 0.45)"
  code_block:
    backgroundColor: "{colors.warm_tool}"
    textColor: "{colors.warm_text}"
    borderColor: "color-mix(in oklab, currentColor 10%, transparent)"
    rounded: "{rounded.field}"
---

## Design North Star

Eye in the Sky should feel like **The Agent Control Room**: compact, calm, and state-first. The interface exists for developers and agent operators who need to understand what is running, what needs attention, who owns work, and what changed, without reading a wall of prose.

This is an operational product, not a marketing surface. Its best screens should resemble a disciplined command console: dense enough for repeated supervision, restrained enough to stay readable for long sessions, and tactile enough that intervention points are obvious.

## Product Personality

The product voice is direct and instrumented. It should prefer short labels, concrete state, and visible traces over decorative explanation. Good EITS copy answers: what happened, what is happening now, what can I do next, and what evidence supports that.

Use the "Eye in the Sky" idea as quiet positioning rather than overt aviation decoration. The UI can borrow from control rooms, terminals, issue trackers, and review consoles, but it should avoid novelty metaphors that hide the actual workflow.

## Visual System

The current system is built around flat tonal layers:

- Rail: the darkest persistent anchor for global navigation.
- Flyout: a slightly lifted command and list surface.
- Canvas: the working field for content and detail views.
- Card/tool/composer: compact, local interaction surfaces.
- Selected state: subtle accent wash plus ring or strip, never a heavy block.

Primary personality should remain the warm Claude/Pampas family. Tokyo Night and Catppuccin can remain as technical/operator themes for users who prefer cooler terminal-like palettes. Do not collapse the product into a single-hue theme; status colors and accents should stay distinct from the base surfaces.

## Layout Principles

Use persistent navigation and compact panels. The app already has a VS Code-like title bar, rail, mobile header, desktop topbar, flyout, and command center. Preserve that structure and make new screens fit into it rather than adding page-level hero sections or ornamental cards.

Default density should be high but organized. Prefer rows, tables, streams, sidebars, tabs, segmented controls, and command bars. Use repeated cards only when each card represents a true repeated object, such as a session, task, message, or job.

## Interaction Principles

Controls should be small, clear, and reachable:

- Icon buttons for navigation, actions, and compact tools.
- Text or icon-and-text buttons for irreversible or high-importance commands.
- Status dots, pills, and subtle color marks for operational state.
- Focus rings and selected states that are visible without being loud.
- Motion in the 100ms to 150ms range for hover, selection, flyout, and width changes.

Every workflow should make ownership, state, and next action visible. Where an action launches agent work, changes task state, sends a DM, or records a commit, the UI should keep the resulting trace nearby.

## Component Guidance

Primary buttons are compact call-to-action controls, usually around `h-7` with small type and an icon when helpful. Ghost icon buttons should stay square, quiet, and clear on hover. Avoid oversized pill buttons in dense operator surfaces.

Session, task, and message rows should use tight spacing, stable heights, status dots, mono metadata, and selected-row accent treatments. Avoid decorative nested cards; nested cards reduce scan speed and make state harder to compare.

Search inputs, filters, and command controls should live close to the list or panel they affect. Empty states should be concise, with one clear next action when available.

Code and command output should preserve monospace readability, copy affordances, and clear boundaries. EITS-CMD blocks should feel like executable operational artifacts, not generic markdown callouts.

## Accessibility And Resilience

The product is used during long monitoring and intervention sessions, so contrast, focus visibility, keyboard navigation, and predictable layout matter. Text should not resize with viewport width, and control dimensions should stay stable across hover, loading, and selected states.

Respect reduced-motion preferences. Use color as a cue, but never as the only cue for critical states such as failed, waiting, blocked, active, approved, or complete.

## Anti-Patterns

Avoid marketing-page composition, oversized heroes, decorative gradients, ornamental blobs, heavy shadows, nested cards, loose spacing, and purely atmospheric imagery. Avoid UI that explains itself with visible instructional prose when a label, icon, tooltip, state, or placement would work better.

Do not introduce external CSS or script assets through layouts. Work through the existing Phoenix, LiveView, Tailwind v4, app.css, app.js, and component system.
