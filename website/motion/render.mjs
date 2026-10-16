// Renders every composition with a transparent background to public/motion/:
// - <id>.webm  VP9 with alpha (Chrome, Firefox, Edge)
// - <id>.mov   HEVC with alpha (Safari, incl. iOS) — macOS `avconvert`
// - <id>.webp  poster with alpha, from the frame where the story is told
// The page picks webm or mov at runtime (Privacy.astro); the loop lies
// directly on the card, so there is no backdrop baked into any file.
// Usage: npm run render  (macOS, ffmpeg from Homebrew)
import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
// sharp resolves from the website's node_modules (ffmpeg builds often lack a WebP encoder).
import sharp from 'sharp';

const out = fileURLToPath(new URL('../public/motion/', import.meta.url));
const tmp = fileURLToPath(new URL('./out/', import.meta.url));
mkdirSync(out, { recursive: true });
mkdirSync(tmp, { recursive: true });

const POSTER_FRAME = 160; // text typed, all three steps shown
const WIDTH = 720;
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });
const ff = (args) => run('ffmpeg', ['-y', '-loglevel', 'error', ...args]);

for (const id of ['privacy-local', 'privacy-cloud']) {
  const master = `${tmp}${id}.mov`;
  run('npx', ['remotion', 'render', 'src/index.ts', id, master, '--codec=prores', '--prores-profile=4444', '--pixel-format=yuva444p10le', '--image-format=png']);
  ff(['-i', master, '-vf', `scale=${WIDTH}:-2`, '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '0', '-crf', '38', '-auto-alt-ref', '0', '-row-mt', '1', '-an', `${out}${id}.webm`]);
  // Safari: Apple's own encoder. ffmpeg's hevc_videotoolbox writes straight
  // alpha that Safari composites as premultiplied — translucent fills turn
  // solid (2026-10-16). avconvert tags the alpha mode correctly.
  const small = `${tmp}${id}-${WIDTH}.mov`;
  ff(['-i', master, '-vf', `scale=${WIDTH}:-2`, '-c:v', 'prores_ks', '-profile:v', '4444', '-pix_fmt', 'yuva444p10le', '-an', small]);
  rmSync(`${out}${id}.mov`, { force: true });
  run('avconvert', ['--source', small, '--output', `${out}${id}.mov`, '--preset', 'PresetHEVCHighestQualityWithAlpha', '--replace']);
  run('npx', ['remotion', 'still', 'src/index.ts', id, `${tmp}${id}.png`, `--frame=${POSTER_FRAME}`, '--image-format=png']);
  await sharp(`${tmp}${id}.png`).resize({ width: WIDTH }).webp({ quality: 82, alphaQuality: 90 }).toFile(`${out}${id}.webp`);
}
rmSync(tmp, { recursive: true, force: true });
