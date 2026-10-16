import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import { localePath, t } from '../../../scripts/i18n.ts';

export async function GET(context: { site?: URL }) {
  const posts = (await getCollection('blog'))
    .filter((post) => post.id.startsWith('en/'))
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());
  return rss({
    title: t('en', 'blog.seoTitle'),
    description: t('en', 'blog.seoDescription'),
    site: context.site ?? 'https://whispaste.de',
    customData: '<language>en</language>',
    items: posts.map((post) => ({
      title: post.data.title,
      description: post.data.description,
      pubDate: post.data.date,
      link: localePath('en', `blog/${post.id.slice('en/'.length)}`),
    })),
  });
}
