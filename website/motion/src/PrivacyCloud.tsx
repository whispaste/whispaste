// Cloud path: the audio packet leaves the device boundary (the crossing
// point flashes amber), the chosen provider processes it and the text packet
// comes back into the field on the user's computer.
import React from 'react';
import { interpolate, useCurrentFrame } from 'remotion';
import { Boundary, Node, StepBadge, Path, SoundRings, Stage, TextCard, TextPacket, WavePill, C, loopFade, mix, progress } from './parts';

const EDGE = 640; // right edge of the boundary
const MIC = { x: 200, y: 220 };
const CARD = { x: 380, y: 440, w: 340, h: 170 };
const CLOUD = { x: 870, y: 330 };

/** y on the straight line a→b at a given x. */
const yAt = (a: { x: number; y: number }, b: { x: number; y: number }, x: number) => a.y + ((b.y - a.y) * (x - a.x)) / (b.x - a.x);

const Crossing: React.FC<{ y: number; flash: number }> = ({ y, flash }) => (
  <div
    style={{
      position: 'absolute',
      left: EDGE - 4 - 20,
      top: y - 20,
      width: 40,
      height: 40,
      borderRadius: 20,
      background: C.amber,
      opacity: flash,
      transform: `scale(${0.6 + flash * 0.6})`,
      boxShadow: `0 0 36px 10px ${C.amber}88`,
    }}
  />
);

export const PrivacyCloud: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = loopFade(frame);

  const listening = interpolate(frame, [0, 6, 36, 48], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const go = progress(frame, 22, 76);
  const arrive = progress(frame, 70, 82);
  const think = interpolate(frame, [76, 86, 104, 116], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const back = progress(frame, 108, 140);
  const typed = progress(frame, 136, 164);

  const outFrom = { x: MIC.x + 66, y: MIC.y };
  // The text packet lands on the window, not behind it.
  const backTo = { x: CARD.x + CARD.w / 2 - 70, y: CARD.y };
  const goX = mix(outFrom.x, CLOUD.x - 76, go);
  const backX = mix(CLOUD.x - 76, backTo.x, back);
  // Flash while a packet is near the boundary edge.
  const near = (x: number, active: boolean) => (active ? Math.max(0, 1 - Math.abs(x - EDGE) / 70) : 0);

  return (
    <Stage>
      <Boundary x={60} y={90} w={EDGE - 60} h={480} pulse={0} />
      <Path x1={outFrom.x} y1={outFrom.y} x2={CLOUD.x - 76} y2={CLOUD.y} lit={go * fade} />
      {/* The line stops at the window edge; the packet travels on onto it. */}
      <Path x1={CLOUD.x - 76} y1={CLOUD.y} x2={CARD.x + CARD.w / 2} y2={yAt({ x: CLOUD.x - 76, y: CLOUD.y }, backTo, CARD.x + CARD.w / 2)} lit={back * fade} />

      <Crossing y={yAt(outFrom, { x: CLOUD.x - 76, y: CLOUD.y }, EDGE)} flash={near(goX, go > 0 && go < 1)} />
      <Crossing y={yAt({ x: CLOUD.x - 76, y: CLOUD.y }, backTo, EDGE)} flash={near(backX, back > 0 && back < 1)} />

      <SoundRings x={MIC.x} y={MIC.y} active={listening} />
      <Node x={MIC.x} y={MIC.y} icon="mic" glow={listening} />

      {/* Provider outside the computer: dashed, with a turning process ring. */}
      <Node x={CLOUD.x} y={CLOUD.y} icon="cloud" glow={think * fade * 0.6} size={152} dashed />
      <svg width={200} height={200} style={{ position: 'absolute', left: CLOUD.x - 100, top: CLOUD.y - 100, opacity: think * fade }}>
        <circle
          cx={100}
          cy={100}
          r={94}
          fill="none"
          stroke={C.cyan}
          strokeWidth={4}
          strokeLinecap="round"
          strokeDasharray="40 30"
          transform={`rotate(${frame * 6} 100 100)`}
        />
      </svg>

      <TextCard x={CARD.x} y={CARD.y} w={CARD.w} h={CARD.h} typed={typed} fade={fade} />

      {go > 0 && arrive < 1 ? (
        <WavePill x={goX} y={yAt(outFrom, { x: CLOUD.x - 76, y: CLOUD.y }, goX)} scale={1 - arrive * 0.85} opacity={1 - arrive} />
      ) : null}
      {back > 0 && back < 1 ? (
        <TextPacket x={backX} y={yAt({ x: CLOUD.x - 76, y: CLOUD.y }, backTo, backX)} opacity={Math.min(1, back * 5) * (1 - progress(frame, 134, 140))} />
      ) : null}
      <StepBadge x={MIC.x - 66} y={MIC.y - 66} n={1} active={listening} />
      <StepBadge x={CLOUD.x - 76} y={CLOUD.y - 76} n={2} active={think * fade} amber />
      <StepBadge x={CARD.x - CARD.w / 2} y={CARD.y - CARD.h / 2} n={3} active={interpolate(typed, [0, 0.1, 0.9, 1], [0, 1, 1, 0]) * fade} />
    </Stage>
  );
};
