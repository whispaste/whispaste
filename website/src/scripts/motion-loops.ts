// Plays the transparent Remotion loops (`<video data-motion-loop="/motion/<id>">`)
// only while on screen and only when the visitor has not asked for reduced
// motion; otherwise the poster frame stays (it already tells the story).
// Rendered by website/motion/render.mjs.
export function initMotionLoops(): void {
  const videos = document.querySelectorAll<HTMLVideoElement>('video[data-motion-loop]:not([data-motion-ready])');
  if (!videos.length || matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)) return;
  // WebKit only keeps alpha in HEVC (.mov), everyone else in VP9 WebM.
  // Picked here because <source> order can't express it.
  const ext = navigator.vendor.startsWith('Apple') ? 'mov' : 'webm';
  const io = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        const v = e.target as HTMLVideoElement;
        if (e.isIntersecting) {
          v.preload = 'auto';
          void v.play().catch(() => {});
        } else {
          v.pause();
        }
      }
    },
    { threshold: 0.35 },
  );
  videos.forEach((v) => {
    v.dataset.motionReady = '';
    v.src = `${v.dataset.motionLoop}.${ext}`;
    io.observe(v);
  });
}
