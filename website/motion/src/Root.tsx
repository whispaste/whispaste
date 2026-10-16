import React from 'react';
import { Composition } from 'remotion';
import { PrivacyCloud } from './PrivacyCloud';
import { PrivacyLocal } from './PrivacyLocal';
import { FPS, H, LOOP, W } from './parts';

export const Root: React.FC = () => (
  <>
    <Composition id="privacy-local" component={PrivacyLocal} durationInFrames={LOOP} fps={FPS} width={W} height={H} />
    <Composition id="privacy-cloud" component={PrivacyCloud} durationInFrames={LOOP} fps={FPS} width={W} height={H} />
  </>
);
