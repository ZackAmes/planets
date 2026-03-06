import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  plugins: [svelte()],
  server: {
    fs: {
      // Allow importing files from the monorepo root (e.g. manifest_sepolia.json)
      allow: ['..'],
    },
  },
})
