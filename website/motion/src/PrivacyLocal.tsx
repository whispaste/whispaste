// Local path: everything happens inside the device boundary. The mic listens,
// the audio packet travels to the on-device engine, the engine consumes it
// (the audio is discarded) and the text lands in the field. The shield pops
// once the whole round trip stayed inside.
import React from 'react';
import { interpolate, spring, useCurrentFrame } from 'remotion';
import { Boundary, FPS, Icon, Node, StepBadge, Path, SoundRings, Stage, TextCard, TextPacket, WavePill, C, loopFade, mix, progress } from './parts';

const MIC = { x: 220, y: 330 };
const CHIP = { x: 520, y: 330 };
const CARD = { x: 820, y: 330, w: 300, h: 210 };

export const PrivacyLocal: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = loopFade(frame);

  const listening = interpolate(frame, [0, 6, 40, 52], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const travel = progress(frame, 26, 70);
  const arrive = progress(frame, 64, 78);
  const think = interpolate(frame, [70, 82, 108, 122], [0, 1, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const ring = progress(frame, 76, 112);
  const out = progress(frame, 110, 132);
  const typed = progress(frame, 128, 160);
  const shield = spring({ frame: frame - 144, fps: FPS, config: { damping: 12, stiffness: 160 } });

  // Discarded audio: a few cyan specks drift up from the engine and vanish.
  const specks = progress(frame, 108, 140);

  return (
    <Stage>
      <Boundary x={70} y={90} w={940} h={480} pulse={shield * fade * 0.8} />
      <Path x1={MIC.x + 66} y1={MIC.y} x2={CHIP.x - 66} y2={CHIP.y} lit={travel * fade} />
      <Path x1={CHIP.x + 66} y1={CHIP.y} x2={CARD.x - CARD.w / 2} y2={CARD.y} lit={out * fade} />

      <SoundRings x={MIC.x} y={MIC.y} active={listening} />
      <Node x={MIC.x} y={MIC.y} icon="mic" glow={listening} />
      <Node x={CHIP.x} y={CHIP.y} icon="cpu" glow={think * fade} />

      {/* Engine progress ring */}
      <svg width={180} height={180} style={{ position: 'absolute', left: CHIP.x - 90, top: CHIP.y - 90, opacity: think * fade }}>
        <circle cx={90} cy={90} r={84} fill="none" stroke={C.cyan} strokeOpacity={0.15} strokeWidth={4} />
        <circle
          cx={90}
          cy={90}
          r={84}
          fill="none"
          stroke={C.cyan}
          strokeWidth={4}
          strokeLinecap="round"
          strokeDasharray={2 * Math.PI * 84}
          strokeDashoffset={2 * Math.PI * 84 * (1 - ring)}
          transform="rotate(-90 90 90)"
        />
      </svg>

      {[-1, 0, 1].map((d, i) => (
        <div
          key={i}
          style={{
            position: 'absolute',
            left: CHIP.x + d * 34 - 5,
            top: CHIP.y - 100 - specks * (60 + i * 18),
            width: 10,
            height: 10,
            borderRadius: 5,
            background: C.cyan,
            opacity: specks > 0 && specks < 1 ? (1 - specks) * 0.8 : 0,
          }}
        />
      ))}

      <TextCard x={CARD.x} y={CARD.y} w={CARD.w} h={CARD.h} typed={typed} fade={fade} />

      {travel > 0 && arrive < 1 ? (
        <WavePill x={mix(MIC.x, CHIP.x, travel)} y={MIC.y - 110 * Math.sin(travel * Math.PI) * 0.35} scale={1 - arrive * 0.85} opacity={1 - arrive} />
      ) : null}
      {out > 0 && out < 1 ? <TextPacket x={mix(CHIP.x + 40, CARD.x - CARD.w / 2 + 70, out)} y={CHIP.y} opacity={Math.min(1, out * 4) * (1 - progress(frame, 126, 132))} /> : null}


      <StepBadge x={MIC.x - 66} y={MIC.y - 66} n={1} active={listening} />
      <StepBadge x={CHIP.x - 66} y={CHIP.y - 66} n={2} active={think * fade} />
      <StepBadge x={CARD.x - CARD.w / 2} y={CARD.y - CARD.h / 2} n={3} active={interpolate(typed, [0, 0.1, 0.9, 1], [0, 1, 1, 0]) * fade} />

      {/* The proof: a shield on the boundary corner once the trip stayed local. */}
      <div
        style={{
          position: 'absolute',
          left: 1010 - 44,
          top: 90 - 44,
          width: 88,
          height: 88,
          borderRadius: 26,
          background: C.amber,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          transform: `scale(${shield}) rotate(${(1 - shield) * -20}deg)`,
          opacity: fade,
          boxShadow: `0 12px 32px ${C.shadow}`,
        }}
      >
        <Icon name="shield" size={48} color={C.onCyan} stroke={2.2} />
      </div>
    </Stage>
  );
};
