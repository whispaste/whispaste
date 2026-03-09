import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://whispaste.github.io',
  base: '/whispaste',
  integrations: [sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
});
