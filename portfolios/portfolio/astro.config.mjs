// @ts-check
import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";
import sitemap from "@astrojs/sitemap";
import tailwind from "@astrojs/tailwind";
import svelte from "@astrojs/svelte";
import react from "@astrojs/react";

// https://astro.build/config
export default defineConfig({
  output: "static",
  site: "https://token-template.deno.dev",
  integrations: [mdx(), sitemap(), tailwind(), svelte(), react()],
  markdown: {
    shikiConfig: {
      theme: "github-dark-high-contrast",
    },
  },
});