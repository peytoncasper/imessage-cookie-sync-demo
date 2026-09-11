import {Composition} from 'remotion';
import {AuthHandoff} from './AuthHandoff';

export const RemotionRoot = () => {
  return (
    <Composition
      id="AuthHandoff"
      component={AuthHandoff}
      durationInFrames={526}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
