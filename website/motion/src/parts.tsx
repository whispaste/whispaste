// Shared building blocks for the privacy motion graphics. Text-free on
// purpose: one render serves all eight site languages, the HTML legend under
// each video carries the words.
import React from 'react';
import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from 'remotion';
import primitives from '../../../design-tokens/primitives.tokens.json';
import semantic from '../../../design-tokens/semantic.dark.tokens.json';

// Resolves a semantic value like "{color.navy.900}" against the primitives.
const resolve = (v: string): string => {
  const ref = /^\{(.+)\}$/.exec(v);
  if (!ref) return v;
  let node: unknown = primitives;
  for (const key of ref[1].split('.')) node = (node as Record<string, unknown>)[key];
  return (node as { $value: string }).$value;
};
const sem = (group: 'surface' | 'border' | 'text' | 'accent', key: string) =>
  resolve((semantic[group] as unknown as Record<string, { $value: string }>)[key].$value);

// Transparent stage: the loop lies directly on the card, so every fill is a
// translucent dark-theme token one step above the card, never an own backdrop.
export const C = {
  node: sem('surface', 'card-hover'),
  nodeBorder: sem('border', 'control'),
  dashed: sem('border', 'strong'),
  dots: sem('border', 'default'),
  tag: sem('surface', 'floating'),
  icon: sem('text', 'primary'),
  line: sem('text', 'secondary'),
  cyan: sem('accent', 'default'),
  onCyan: sem('accent', 'on-fill'),
  amber: primitives.color.amber['400'].$value,
  shadow: `${primitives.color.navy['950'].$value}66`,
};

const MONO = (primitives.font.family as unknown as { mono: { $value: string[] } }).mono.$value.join(', ');

export const W = 1080;
export const H = 640;
export const FPS = 30;
export const LOOP = 180;

export const ease = Easing.bezier(0.22, 1, 0.36, 1);
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

/** 0→1 over [from, to] with the site's flow easing. */
export const progress = (frame: number, from: number, to: number) =>
  interpolate(frame, [from, to], [0, 1], { ...clamp, easing: ease });

/** Fades the moving layers out at the end so the loop restarts seamlessly. */
export const loopFade = (frame: number) => interpolate(frame, [LOOP - 18, LOOP - 2], [1, 0], clamp);

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;

type IconName = 'mic' | 'cpu' | 'cloud' | 'laptop' | 'shield';
const ICONS: Record<IconName, React.ReactNode> = {
  mic: (
    <>
      <path d="M12 19v3" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <rect x="9" y="2" width="6" height="13" rx="3" />
    </>
  ),
  cpu: (
    <>
      <path d="M12 20v2M12 2v2M17 20v2M17 2v2M2 12h2M2 17h2M2 7h2M20 12h2M20 17h2M20 7h2M7 20v2M7 2v2" />
      <rect x="4" y="4" width="16" height="16" rx="2" />
      <rect x="8" y="8" width="8" height="8" rx="1" />
    </>
  ),
  cloud: <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />,
  laptop: (
    <>
      <path d="M18 5a2 2 0 0 1 2 2v8.526a2 2 0 0 0 .212.897l1.068 2.127a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45l1.068-2.127A2 2 0 0 0 4 15.526V7a2 2 0 0 1 2-2z" />
      <path d="M20.054 15.987H3.946" />
    </>
  ),
  shield: (
    <>
      <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />
      <path d="m9 12 2 2 4-4" />
    </>
  ),
};

export const Icon: React.FC<{ name: IconName; size: number; color: string; stroke?: number }> = ({
  name,
  size,
  color,
  stroke = 1.75,
}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
    {ICONS[name]}
  </svg>
);

/** Transparent stage: the card behind the video is the backdrop. A baked-in
 *  halftone was dropped — full-frame dots tripled the alpha video size. */
export const Stage: React.FC<{ children: React.ReactNode }> = ({ children }) => <AbsoluteFill>{children}</AbsoluteFill>;

/** The dashed "your computer" boundary; the dashes crawl slowly. */
export const Boundary: React.FC<{ x: number; y: number; w: number; h: number; pulse: number }> = ({ x, y, w, h, pulse }) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ position: 'absolute', left: x, top: y, width: w, height: h }}>
      <svg width={w} height={h} style={{ position: 'absolute', inset: 0, overflow: 'visible' }}>
        <rect
          x={2}
          y={2}
          width={w - 4}
          height={h - 4}
          rx={28}
          fill={C.cyan}
          fillOpacity={0.03 + pulse * 0.05}
          stroke={C.cyan}
          strokeOpacity={0.55 + pulse * 0.45}
          strokeWidth={3}
          strokeDasharray="14 12"
          strokeDashoffset={-frame * 0.6}
        />
      </svg>
      <div
        style={{
          position: 'absolute',
          left: 26,
          top: -22,
          padding: '8px 12px',
          borderRadius: 14,
          background: C.tag,
          border: `2px solid ${C.cyan}`,
          display: 'flex',
        }}
      >
        <Icon name="laptop" size={26} color={C.cyan} />
      </div>
    </div>
  );
};

/** Step number, the same digit and colour as the legend under the video.
 *  Digits are language-neutral, so the one render still fits every locale. */
export const StepBadge: React.FC<{ x: number; y: number; n: number; active: number; amber?: boolean }> = ({ x, y, n, active, amber = false }) => (
  <div
    style={{
      position: 'absolute',
      left: x - 24,
      top: y - 24,
      width: 48,
      height: 48,
      borderRadius: 24,
      background: amber ? C.amber : C.cyan,
      color: C.onCyan,
      fontFamily: MONO,
      fontSize: 24,
      fontWeight: 700,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      transform: `scale(${1 + active * 0.18})`,
      boxShadow: `0 0 ${active * 28}px ${active * 4}px ${amber ? C.amber : C.cyan}66, 0 8px 18px ${C.shadow}`,
    }}
  >
    {n}
  </div>
);

/** A round node with an icon; `glow` 0..1 lights it up. */
export const Node: React.FC<{ x: number; y: number; icon: IconName; glow: number; size?: number; dashed?: boolean }> = ({
  x,
  y,
  icon,
  glow,
  size = 132,
  dashed = false,
}) => (
  <div
    style={{
      position: 'absolute',
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      borderRadius: size * 0.3,
      background: dashed ? 'transparent' : C.node,
      border: `2px ${dashed ? 'dashed' : 'solid'} ${dashed ? C.dashed : C.nodeBorder}`,
      boxShadow: `0 0 ${12 + glow * 48}px ${glow * 6}px ${C.cyan}${Math.round(glow * 90)
        .toString(16)
        .padStart(2, '0')}${dashed ? '' : `, 0 18px 40px ${C.shadow}`}`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
    }}
  >
    <Icon name={icon} size={size * 0.46} color={glow > 0.05 ? C.cyan : C.icon} />
  </div>
);

/** Expanding sound rings around the mic while it listens. */
export const SoundRings: React.FC<{ x: number; y: number; active: number }> = ({ x, y, active }) => {
  const frame = useCurrentFrame();
  return (
    <>
      {[0, 1, 2].map((i) => {
        const t = ((frame + i * 12) % 36) / 36;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: x - 66 - t * 50,
              top: y - 66 - t * 50,
              width: 132 + t * 100,
              height: 132 + t * 100,
              borderRadius: 60,
              border: `2px solid ${C.cyan}`,
              opacity: (1 - t) * 0.5 * active,
            }}
          />
        );
      })}
    </>
  );
};

/** The audio packet: a speech-bubble-like pill with live wave bars. */
export const WavePill: React.FC<{ x: number; y: number; scale: number; opacity: number }> = ({ x, y, scale, opacity }) => {
  const frame = useCurrentFrame();
  const bars = 7;
  return (
    <div
      style={{
        position: 'absolute',
        left: x - 70,
        top: y - 30,
        width: 140,
        height: 60,
        borderRadius: 30,
        background: C.cyan,
        boxShadow: `0 0 32px 4px ${C.cyan}66`,
        transform: `scale(${scale})`,
        opacity,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 7,
      }}
    >
      {Array.from({ length: bars }, (_, i) => {
        const h = 10 + Math.abs(Math.sin(frame / 4 + i * 0.9)) * 26;
        return <div key={i} style={{ width: 7, height: h, borderRadius: 4, background: C.onCyan }} />;
      })}
    </div>
  );
};

/** Small packet carrying the finished text (three short lines). */
export const TextPacket: React.FC<{ x: number; y: number; opacity: number }> = ({ x, y, opacity }) => (
  <div
    style={{
      position: 'absolute',
      left: x - 34,
      top: y - 26,
      width: 68,
      height: 52,
      borderRadius: 14,
      background: C.icon,
      boxShadow: `0 0 28px 2px ${C.cyan}55`,
      opacity,
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'center',
      gap: 6,
      padding: '0 14px',
    }}
  >
    {[1, 0.7, 0.85].map((w, i) => (
      <div key={i} style={{ height: 5, width: `${w * 100}%`, borderRadius: 3, background: C.onCyan }} />
    ))}
  </div>
);

/** The text field the dictation lands in: lines type out, caret blinks. */
export const TextCard: React.FC<{ x: number; y: number; w: number; h: number; typed: number; fade: number }> = ({
  x,
  y,
  w,
  h,
  typed,
  fade,
}) => {
  const frame = useCurrentFrame();
  const lines = [0.92, 0.78, 0.55];
  const caretOn = Math.floor(frame / 9) % 2 === 0;
  // Which line the caret sits on, and how far it has run.
  const total = typed * lines.length;
  const active = Math.min(lines.length - 1, Math.floor(total));
  return (
    <div
      style={{
        position: 'absolute',
        left: x - w / 2,
        top: y - h / 2,
        width: w,
        height: h,
        borderRadius: 22,
        background: C.node,
        border: `2px solid ${C.nodeBorder}`,
        boxShadow: `0 18px 40px ${C.shadow}`,
        padding: '28px 28px',
        display: 'flex',
        flexDirection: 'column',
        gap: 16,
      }}
    >
      <div style={{ display: 'flex', gap: 8, marginBottom: 4 }}>
        {[0, 1, 2].map((i) => (
          <div key={i} style={{ width: 10, height: 10, borderRadius: 5, background: C.nodeBorder }} />
        ))}
      </div>
      {lines.map((full, i) => {
        const part = Math.max(0, Math.min(1, total - i));
        return (
          <div key={i} style={{ position: 'relative', height: 12 }}>
            <div
              style={{
                height: 12,
                width: `${full * part * 100}%`,
                borderRadius: 6,
                background: C.line,
                opacity: fade,
              }}
            />
            {i === active && typed > 0 && fade > 0.5 ? (
              <div
                style={{
                  position: 'absolute',
                  left: `calc(${full * part * 100}% + 6px)`,
                  top: -6,
                  width: 4,
                  height: 24,
                  borderRadius: 2,
                  background: C.cyan,
                  opacity: caretOn || part < 1 ? 1 : 0,
                }}
              />
            ) : null}
          </div>
        );
      })}
    </div>
  );
};

/** Dotted connector between two points. */
export const Path: React.FC<{ x1: number; y1: number; x2: number; y2: number; lit: number }> = ({ x1, y1, x2, y2, lit }) => (
  <svg width={W} height={H} style={{ position: 'absolute', inset: 0 }}>
    <line x1={x1} y1={y1} x2={x2} y2={y2} stroke={C.dashed} strokeWidth={3} strokeDasharray="2 12" strokeLinecap="round" />
    <line
      x1={x1}
      y1={y1}
      x2={mix(x1, x2, lit)}
      y2={mix(y1, y2, lit)}
      stroke={C.cyan}
      strokeOpacity={0.7}
      strokeWidth={3}
      strokeDasharray="2 12"
      strokeLinecap="round"
    />
  </svg>
);
