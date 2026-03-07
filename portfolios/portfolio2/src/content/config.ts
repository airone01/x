/* eslint-disable @typescript-eslint/no-unsafe-call */
/* eslint-disable @typescript-eslint/no-unsafe-assignment */
import {defineCollection, z} from 'astro:content';

export const wallpapers = [
  'https://images.unsplash.com/photo-1534379123277-8853f132516f',
  'https://images.unsplash.com/photo-1496044654355-e8102baadbf4',
  'https://i.imgur.com/2lHK6eH.jpeg',
] as const;

const blog = defineCollection({
  type: 'content',
  // Type-check frontmatter using a schema
  schema: z.object({
    title: z.string(),
    description: z.string(),
    // Transform string to Date object
    pubDate: z.coerce.date(),
    updatedDate: z.coerce.date().optional(),
    heroImage: z.enum(wallpapers),
  }),
});

const projects = defineCollection({
  type: 'content',
  // Type-check frontmatter using a schema
  schema: z.object({
    title: z.string(),
    description: z.string(),
    // Transform string to Date object
    heroImage: z.string().optional(),
  }),
});

export const collections = {blog, projects};
