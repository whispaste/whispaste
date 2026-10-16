import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

/**
 * Blog posts live in `src/content/blog/<locale>/<slug>.md`. The blog is
 * published in German and English only; a post exists in both languages
 * under the same slug (see `isBlogSlug` in `scripts/locales.ts`).
 */
const blog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/blog' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    date: z.coerce.date(),
    /** Optional own cover image; without it the post gets the generated waveform cover. */
    cover: z.object({ src: z.string(), alt: z.string(), og: z.string().optional() }).optional(),
  }),
});

export const collections = { blog };
