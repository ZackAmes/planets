import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import mkcert from 'vite-plugin-mkcert'

export default defineConfig({
  plugins: [mkcert(), svelte()],
  server: {
    port: 5173,
    strictPort: true,
    fs: {
      // Allow importing files from the monorepo root (e.g. manifest_sepolia.json)
      allow: ['..'],
    },
  },
})
