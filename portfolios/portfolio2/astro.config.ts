import {defineConfig} from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import icon from 'astro-icon';
import tailwind from '@astrojs/tailwind';
import alpinejs from '@astrojs/alpinejs';
import react from '@astrojs/react';

// https://astro.build/config
export default defineConfig({
  site: 'https://elagouche.fr',
  integrations: [mdx(), sitemap(), icon(), tailwind(), alpinejs(), react()],
});
