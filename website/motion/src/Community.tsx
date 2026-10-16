// Open source: four ways in (1 issue, 2 pull request, 3 idea, 4 translation)
// each send a packet along their path into the WhisPaste hub. Every arrival
// fills a quarter of the hub's ring; when all four are in, the amber release
// tag pops — together they ship the next version. Numbers match the cards
// under the video.
import React from 'react';
import { interpolate, spring, useCurrentFrame } from 'remotion';
import { C, FPS, Icon, type IconName, Node, Path, Stage, StepBadge, loopFade, mix, progress } from './parts';

const HUB = { x: 540, y: 320 };
const HUB_SIZE = 176;
const WAYS: { x: number; y: number; icon: IconName }[] = [
  { x: 190, y: 150, icon: 'issue' },
  { x: 890, y: 150, icon: 'pull' },
  { x: 190, y: 490, icon: 'idea' },
  { x: 890, y: 490, icon: 'languages' },
];
const START = 8;
const STAGGER = 24;
const TRAVEL = 30;
const RING_R = 112;

/** Point on the line from a to b, `inset` px in from a's centre. */
const edge = (a: { x: number; y: number }, b: { x: number; y: number }, inset: number) => {
  const len = Math.hypot(b.x - a.x, b.y - a.y);
  return { x: a.x + ((b.x - a.x) / len) * inset, y: a.y + ((b.y - a.y) / len) * inset };
};

export const Community: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = loopFade(frame);
  const travel = WAYS.map((_, i) => progress(frame, START + i * STAGGER, START + i * STAGGER + TRAVEL));
  const arrived = travel.filter((t) => t >= 1).length;
  // The ring fills smoothly, a quarter per arrival.
  const ring = travel.reduce((sum, t) => sum + progress(t, 0.85, 1), 0) / WAYS.length;
  const lastArrival = START + (WAYS.length - 1) * STAGGER + TRAVEL;
  const hubBump = WAYS.reduce((max, _, i) => {
    const at = START + i * STAGGER + TRAVEL;
    return Math.max(max, interpolate(frame, [at - 2, at + 4, at + 14], [0, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }));
  }, 0);
  const release = spring({ frame: frame - (lastArrival + 8), fps: FPS, config: { damping: 11, stiffness: 150 } });

  return (
    <Stage>
      {WAYS.map((w, i) => {
        const from = edge(w, HUB, 66);
        const to = edge(HUB, w, RING_R + 6);
        return <Path key={i} x1={from.x} y1={from.y} x2={to.x} y2={to.y} lit={travel[i] * fade} />;
      })}

      {/* Hub ring: one quarter per contribution. */}
      <svg width={RING_R * 2 + 12} height={RING_R * 2 + 12} style={{ position: 'absolute', left: HUB.x - RING_R - 6, top: HUB.y - RING_R - 6, opacity: fade }}>
        <circle cx={RING_R + 6} cy={RING_R + 6} r={RING_R} fill="none" stroke={C.dashed} strokeWidth={4} strokeDasharray="2 12" strokeLinecap="round" />
        <circle
          cx={RING_R + 6}
          cy={RING_R + 6}
          r={RING_R}
          fill="none"
          stroke={C.cyan}
          strokeWidth={5}
          strokeLinecap="round"
          strokeDasharray={2 * Math.PI * RING_R}
          strokeDashoffset={2 * Math.PI * RING_R * (1 - ring)}
          transform={`rotate(-90 ${RING_R + 6} ${RING_R + 6})`}
        />
      </svg>

      <div style={{ position: 'absolute', inset: 0, transform: `scale(${1 + hubBump * 0.04})`, transformOrigin: `${HUB.x}px ${HUB.y}px` }}>
        <Node x={HUB.x} y={HUB.y} icon="wave" size={HUB_SIZE} glow={Math.max(hubBump, (arrived / WAYS.length) * 0.5) * fade} />
      </div>

      {WAYS.map((w, i) => {
        const sending = interpolate(travel[i], [0, 0.05, 0.6, 1], [0, 1, 1, 0]);
        return <Node key={i} x={w.x} y={w.y} icon={w.icon} glow={sending * fade} />;
      })}

      {/* Packets: a small chip carrying the way's icon. */}
      {WAYS.map((w, i) => {
        const t = travel[i];
        if (t <= 0 || t >= 1) return null;
        const from = edge(w, HUB, 66);
        const to = edge(HUB, w, HUB_SIZE / 2);
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: mix(from.x, to.x, t) - 30,
              top: mix(from.y, to.y, t) - 30,
              width: 60,
              height: 60,
              borderRadius: 18,
              background: C.cyan,
              boxShadow: `0 0 28px 4px ${C.cyan}55`,
              opacity: Math.min(1, t * 6) * (1 - progress(t, 0.9, 1)),
              transform: `scale(${1 - progress(t, 0.8, 1) * 0.5})`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Icon name={w.icon} size={32} color={C.onCyan} stroke={2.2} />
          </div>
        );
      })}

      {WAYS.map((w, i) => (
        <StepBadge
          key={i}
          x={w.x + (w.x < HUB.x ? -66 : 66)}
          y={w.y - 66}
          n={i + 1}
          active={interpolate(travel[i], [0, 0.05, 0.6, 1], [0, 1, 1, 0]) * fade}
        />
      ))}

      {/* The release: an amber tag pops on the hub once all four are in. */}
      <div
        style={{
          position: 'absolute',
          left: HUB.x + 70 - 40,
          top: HUB.y - 70 - 40,
          width: 80,
          height: 80,
          borderRadius: 24,
          background: C.amber,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          transform: `scale(${release}) rotate(${(1 - release) * -24}deg)`,
          opacity: fade,
          boxShadow: `0 12px 32px ${C.shadow}`,
        }}
      >
        <Icon name="tag" size={42} color={C.onCyan} stroke={2.2} />
      </div>
    </Stage>
  );
};
