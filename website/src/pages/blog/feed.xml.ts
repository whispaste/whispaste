import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import { localePath, t } from '../../scripts/i18n.ts';

export async function GET(context: { site?: URL }) {
  const posts = (await getCollection('blog'))
    .filter((post) => post.id.startsWith('de/'))
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());
  return rss({
    title: t('de', 'blog.seoTitle'),
    description: t('de', 'blog.seoDescription'),
    site: context.site ?? 'https://whispaste.de',
    customData: '<language>de</language>',
    items: posts.map((post) => ({
      title: post.data.title,
      description: post.data.description,
      pubDate: post.data.date,
      link: localePath('de', `blog/${post.id.slice('de/'.length)}`),
    })),
  });
}
