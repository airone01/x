import type {APIRoute} from 'astro';

const robotsTxt = `
User-agent: *
Allow: /

Sitemap: ${new URL('sitemap-index.xml', import.meta.env.SITE).href}
`.trim();

// eslint-disable-next-line @typescript-eslint/naming-convention
export const GET: APIRoute = () => new Response(robotsTxt, {
  headers: {
    'Content-Type': 'text/plain; charset=utf-8',
  },
});
