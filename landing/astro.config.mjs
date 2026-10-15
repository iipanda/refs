// @ts-check
import { defineConfig } from 'astro/config';
import svelte from '@astrojs/svelte';

export default defineConfig({
  site: 'https://refsapp.pages.dev',
  integrations: [svelte()],
  // Zero-specificity scoping keeps the stylesheet's original cascade.
  scopedStyleStrategy: 'where',
  server: { host: '127.0.0.1', port: 8770 },
});
