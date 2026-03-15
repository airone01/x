import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";
import { SITE } from "@/config";

export const INSTANCES_PATH = "src/data/instances";
export const SOFTWARE_PATH = "src/data/software";

const instances = defineCollection({
  loader: glob({
    pattern: "**/[^_]*.{md,mdx}",
    base: `./${INSTANCES_PATH}`,
  }),
  schema: ({ image }) =>
    z.object({
      author: z.string().default(SITE.author),
      pubDatetime: z.date(),
      modDatetime: z.date().optional().nullable(),
      title: z.string(),
      featured: z.boolean().optional(),
      draft: z.boolean().optional(),
      tags: z.array(z.string()).default(["others"]),
      ogImage: image().or(z.string()).optional(),
      description: z.string(),
      canonicalURL: z.string().optional(),
      hideEditPost: z.boolean().optional(),
      timezone: z.string().optional(),
    }),
});

const software = defineCollection({
  loader: glob({ pattern: "**/[^_]*.{md,mdx}", base: `./${SOFTWARE_PATH}` }),
  schema: ({ image }) =>
    z.object({
      title: z.string(),
      description: z.string(),
      website: z.string().url(),
      github: z.string().url().optional(),
      logo: image().or(z.string()).optional(),
    }),
});

export const collections = { instances, software };
