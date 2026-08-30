import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vuetify from 'vite-plugin-vuetify'

// The site is published as a GitHub project page, so everything is served from
// /glassdeck/ rather than from the root — in dev and preview too.
export default defineConfig({
  // Unconditionally, including `vite preview`: preview runs as a `serve`
  // command, so making this conditional pointed the preview server at / while
  // the built index.html asked for /glassdeck/, and every asset came back as
  // the SPA fallback index.html with a 200.
  base: '/glassdeck/',
  plugins: [vue(), vuetify({ autoImport: true })],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      // The screenshots live with the README rather than being copied here, so
      // there is one set of images to keep current.
      '#images': fileURLToPath(new URL('../docs/images', import.meta.url)),
    },
  },
  server: {
    // ../docs/images sits outside the Vite root.
    fs: { allow: ['..'] },
  },
  build: {
    outDir: 'dist',
    assetsInlineLimit: 0,
  },
})
