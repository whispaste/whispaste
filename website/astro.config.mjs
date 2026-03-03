import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://whispaste.github.io',
  base: '/whispaste',
  vite: {
    plugins: [tailwindcss()],
  },
});
