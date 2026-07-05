import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import liveSveltePlugin from "live_svelte/vitePlugin"
import { phoenixVitePlugin } from "phoenix_vite"

const isSSR = process.argv.includes("--ssr")

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: parseInt(process.env.VITE_PORT || "5173"),
    strictPort: true,
    cors: true,
  },
  optimizeDeps: {
    include: [
      "phoenix",
      "phoenix_html",
      "phoenix_live_view",
      // CM6 core — must be in the same pre-bundled chunk as svelte-codemirror-editor
      // to avoid duplicate @codemirror/state instances (breaks instanceof checks)
      "@codemirror/state",
      "@codemirror/view",
      "@codemirror/language",
      // Language packages — pre-bundle so dynamic imports resolve to the same instance
      "@codemirror/lang-javascript",
      "@codemirror/lang-css",
      "@codemirror/lang-html",
      "@codemirror/lang-json",
      "@codemirror/lang-markdown",
      "codemirror-lang-elixir",
      // Theme packages
      "@codemirror/theme-one-dark",
      "@uiw/codemirror-theme-dracula",
      "@uiw/codemirror-theme-tokyo-night",
      "@uiw/codemirror-theme-eclipse",
      "@uiw/codemirror-theme-bespin",
    ],
  },
  build: isSSR
    ? {
        // SSR build: CJS format so NodeJS.call! (which uses require()) can load it
        rollupOptions: {
          output: { format: "cjs", entryFileNames: "[name].js" },
        },
      }
    : {
        manifest: true,
        rollupOptions: {
          input: ["js/app.js"],
          output: {
            // CRITICAL: Keep app.js in a single chunk to prevent double LiveSocket binding
            // in production. Code-splitting caused the main app initialization to run
            // in a different order vs dev, resulting in duplicate data-phx-root-id.
            // Dynamic imports from split chunks (editor, syntax) were causing module
            // re-evaluation, leading to "Cannot bind multiple views" error on DM page.
            manualChunks: undefined,
          },
        },
        outDir: "../priv/static",
        emptyOutDir: false,
      },
  resolve: {
    alias: {
      "@": ".",
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
    // Force single instance of CM6 core packages — prevents duplicate @codemirror/state
    // which breaks instanceof checks when language/theme extensions are loaded dynamically.
    dedupe: ["@codemirror/state", "@codemirror/view", "@codemirror/language"],
  },
  assetsInclude: [],
  plugins: [
    svelte({ compilerOptions: { css: "injected" } }),
    liveSveltePlugin({ entrypoint: "./js/server.js" }),
    phoenixVitePlugin({ pattern: /\.(ex|heex)$/ }),
  ],
  ssr: {
    noExternal: process.env.NODE_ENV === "production" ? true : ["svelte-codemirror-editor"],
  },
})
