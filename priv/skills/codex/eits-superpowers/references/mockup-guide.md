# EITS Mockup Guide

Reference for creating HTML mockups in the EITS project style.

## File Location

```
priv/static/mockups/<feature-name>.html
```

Open with: `open priv/static/mockups/<feature-name>.html`

## Theme Variables

```css
:root {
  --bg: #0f1117;        /* page background */
  --surface: #1a1d27;   /* card/panel background */
  --surface2: #22263a;  /* elevated surface (titlebar, hover) */
  --border: #2e3348;    /* borders */
  --accent: #6366f1;    /* primary accent (indigo) */
  --accent2: #818cf8;   /* lighter accent */
  --text: #e2e8f0;      /* primary text */
  --muted: #64748b;     /* secondary/muted text */
  --green: #22c55e;     /* success/active */
  --yellow: #f59e0b;    /* warning/pending */
}
```

## Standard Components

### Mockup Frame (browser chrome)

```html
<div class="mockup-frame">
  <div class="mockup-titlebar">
    <div class="dot dot-r"></div>
    <div class="dot dot-y"></div>
    <div class="dot dot-g"></div>
    <div class="mockup-url">localhost:5001/<route></div>
  </div>
  <div class="app-body">
    <!-- sidebar + content -->
  </div>
</div>
```

### App Sidebar

```html
<div class="app-sidebar">
  <div class="nav-icon">icon1</div>
  <div class="nav-icon active">icon2</div>
  <div class="nav-icon">icon3</div>
</div>
```

### View Tabs (top-level state switcher)

```html
<div class="view-tabs">
  <div class="tab active" onclick="show('list', this)">List View</div>
  <div class="tab" onclick="show('form', this)">Form View</div>
  <div class="tab" onclick="show('side', this)">Side by Side</div>
</div>
```

### Annotation Block

```html
<div class="annotation">
  <strong>Key point:</strong> Explanation of behavior.
  Data from <code>context_name</code>. Implementation note here.
</div>
```

### Mobile Drawer

```html
<div class="drawer-overlay"></div>
<div class="drawer">
  <!-- form content -->
</div>
```

### Desktop Modal

```html
<div class="modal-overlay">
  <div class="modal">
    <!-- form content -->
  </div>
</div>
```

## Tab Switching Script

```html
<script>
  function show(id, el) {
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    document.getElementById('view-' + id).classList.add('active');
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    el.classList.add('active');
  }
</script>
```

## Checklist

- [ ] Dark theme variables applied
- [ ] App chrome (sidebar, header) for context
- [ ] View tabs for different states
- [ ] Mobile variant (drawer) for forms
- [ ] Desktop variant (modal) for forms
- [ ] Annotation blocks explaining data sources and behavior
- [ ] Side-by-side comparison view if mobile/desktop differ
- [ ] Realistic data (not "Lorem ipsum")
