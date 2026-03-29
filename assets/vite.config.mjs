import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import liveSveltePlugin from "live_svelte/vitePlugin"
import { phoenixVitePlugin } from "phoenix_vite"

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
    cors: true,
  },
  optimizeDeps: {
    include: ["phoenix", "phoenix_html", "phoenix_live_view"],
  },
  build: {
    manifest: true,
    rollupOptions: {
      input: ["js/app.js"],
    },
    outDir: "../priv/static",
    emptyOutDir: false,
  },
  resolve: {
    alias: {
      "@": ".",
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
  },
  assetsInclude: [],
  plugins: [
    svelte({ compilerOptions: { css: "injected" } }),
    liveSveltePlugin({ entrypoint: "./js/server.js" }),
    phoenixVitePlugin({ pattern: /\.(ex|heex)$/ }),
  ],
  ssr: {
    noExternal: process.env.NODE_ENV === "production" ? true : undefined,
  },
})
