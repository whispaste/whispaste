import { getCollection } from 'astro:content';
import { buildFeed } from '../../../scripts/blog.ts';
import { t } from '../../../scripts/i18n.ts';

export async function GET() {
  const posts = (await getCollection('blog'))
    .filter((post) => post.id.startsWith('en/'))
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf())
    .map((post) => ({
      slug: post.id.slice('en/'.length),
      title: post.data.title,
      description: post.data.description,
      date: post.data.date,
    }));
  const body = buildFeed('en', t('en', 'blog.seoTitle'), t('en', 'blog.seoDescription'), posts);
  return new Response(body, { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } });
}
