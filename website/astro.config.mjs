import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://silvio-l.github.io',
  base: '/whispaste',
  vite: {
    plugins: [tailwindcss()],
  },
});
