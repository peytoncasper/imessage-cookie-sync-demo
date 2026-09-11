import {Video} from '@remotion/media';
import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const ORANGE = '#FF4500';
const REVEAL_FRAME = 390;

const BrowserbaseMark = ({size = 42}: {size?: number}) => (
  <svg width={size} height={size} viewBox="0 0 200 200" aria-label="Browserbase">
    <rect width="200" height="200" rx="32" fill={ORANGE} />
    <path
      d="M55.445 147.815h73.233l16.581-16.581v-19.343l-13.818-13.819 11.054-11.053V69.056l-16.581-16.58H55.445Z"
      fill="white"
    />
    <path d="M83.168 79.208h28v7h-28zM83.168 109.901h28v7h-28z" fill={ORANGE} />
  </svg>
);

const GridBackground = () => (
  <AbsoluteFill
    style={{
      background:
        'radial-gradient(circle at 14% 18%, rgba(255,69,0,.22), transparent 31%), radial-gradient(circle at 87% 76%, rgba(255,69,0,.12), transparent 29%), linear-gradient(145deg, #0d0b09 0%, #060605 55%, #0d0907 100%)',
    }}
  >
    <AbsoluteFill
      style={{
        opacity: 0.16,
        backgroundImage:
          'linear-gradient(rgba(255,255,255,.08) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.08) 1px, transparent 1px)',
        backgroundSize: '64px 64px',
        maskImage: 'linear-gradient(to bottom, black, transparent 86%)',
      }}
    />
    <div
      style={{
        position: 'absolute',
        width: 520,
        height: 520,
        borderRadius: '50%',
        left: -190,
        top: 560,
        border: '1px solid rgba(255,69,0,.28)',
        boxShadow: '0 0 100px rgba(255,69,0,.08) inset',
      }}
    />
  </AbsoluteFill>
);

const Label = ({number, children}: {number: string; children: React.ReactNode}) => (
  <div
    style={{
      height: 36,
      display: 'flex',
      alignItems: 'center',
      gap: 11,
      color: 'rgba(255,255,255,.74)',
      fontSize: 17,
      fontWeight: 700,
      letterSpacing: 1.3,
      textTransform: 'uppercase',
    }}
  >
    <span
      style={{
        width: 29,
        height: 29,
        borderRadius: 10,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'rgba(255,69,0,.16)',
        border: '1px solid rgba(255,69,0,.55)',
        color: '#ff7847',
        fontSize: 15,
      }}
    >
      {number}
    </span>
    {children}
  </div>
);

const DeviceFrame = ({children}: {children: React.ReactNode}) => (
  <div
    style={{
      position: 'relative',
      width: 298,
      height: 647,
      padding: 8,
      boxSizing: 'border-box',
      borderRadius: 42,
      background: 'linear-gradient(150deg, #3c3b3b, #0d0d0d 44%, #292727)',
      boxShadow: '0 28px 70px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.14)',
    }}
  >
    <div
      style={{
        width: '100%',
        height: '100%',
        overflow: 'hidden',
        borderRadius: 35,
        background: '#fff',
        position: 'relative',
      }}
    >
      {children}
    </div>
    <div
      style={{
        position: 'absolute',
        top: 16,
        left: '50%',
        transform: 'translateX(-50%)',
        width: 84,
        height: 24,
        borderRadius: 20,
        background: '#050505',
        zIndex: 4,
      }}
    />
  </div>
);

const WaitingState = ({opacity}: {opacity: number}) => {
  const frame = useCurrentFrame();
  const pulse = interpolate(Math.sin(frame / 10), [-1, 1], [0.78, 1]);

  return (
    <AbsoluteFill
      style={{
        opacity,
        alignItems: 'center',
        justifyContent: 'center',
        background:
          'radial-gradient(circle at center, rgba(255,69,0,.13), transparent 42%), linear-gradient(135deg, #17130f, #090807)',
      }}
    >
      <div style={{transform: `scale(${pulse})`, filter: 'drop-shadow(0 18px 34px rgba(255,69,0,.22))'}}>
        <BrowserbaseMark size={76} />
      </div>
      <div style={{marginTop: 25, color: '#fff', fontSize: 30, fontWeight: 720}}>Live session ready</div>
      <div style={{marginTop: 9, color: 'rgba(255,255,255,.53)', fontSize: 19}}>
        Waiting for authenticated cookies…
      </div>
      <div
        style={{
          marginTop: 28,
          display: 'flex',
          alignItems: 'center',
          gap: 9,
          padding: '10px 15px',
          borderRadius: 999,
          background: 'rgba(255,255,255,.055)',
          border: '1px solid rgba(255,255,255,.09)',
          color: 'rgba(255,255,255,.65)',
          fontSize: 15,
        }}
      >
        <span
          style={{
            width: 8,
            height: 8,
            borderRadius: '50%',
            background: ORANGE,
            boxShadow: `0 0 ${10 + pulse * 8}px ${ORANGE}`,
          }}
        />
        Browserbase recording live
      </div>
    </AbsoluteFill>
  );
};

const BrowserPanel = () => {
  const frame = useCurrentFrame();
  const videoOpacity = interpolate(frame, [REVEAL_FRAME, REVEAL_FRAME + 10], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.quad),
  });
  const waitingOpacity = interpolate(frame, [REVEAL_FRAME - 5, REVEAL_FRAME + 8], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const success = spring({
    frame: frame - REVEAL_FRAME - 6,
    fps: 30,
    config: {damping: 200},
  });

  return (
    <div
      style={{
        width: 1120,
        height: 630,
        borderRadius: 27,
        padding: 8,
        boxSizing: 'border-box',
        background: 'linear-gradient(145deg, rgba(255,255,255,.22), rgba(255,255,255,.035))',
        boxShadow: '0 30px 78px rgba(0,0,0,.48), 0 0 0 1px rgba(255,255,255,.07)',
      }}
    >
      <div
        style={{
          position: 'relative',
          width: '100%',
          height: '100%',
          borderRadius: 20,
          overflow: 'hidden',
          background: '#0b0b0b',
        }}
      >
        <WaitingState opacity={waitingOpacity} />

        <Sequence from={REVEAL_FRAME} premountFor={60}>
          <Video
            src={staticFile('browser.mp4')}
            trimBefore={24.3 * 30}
            muted
            style={{
              position: 'absolute',
              width: 1493,
              height: 840,
              left: -187,
              top: 0,
              opacity: videoOpacity,
              objectFit: 'fill',
            }}
          />
        </Sequence>

        {frame >= REVEAL_FRAME && (
          <div
            style={{
              position: 'absolute',
              zIndex: 5,
              right: 18,
              top: 18,
              display: 'flex',
              alignItems: 'center',
              gap: 9,
              padding: '10px 15px',
              borderRadius: 999,
              background: 'rgba(7,20,12,.89)',
              border: '1px solid rgba(73,230,132,.42)',
              color: '#aaf4c4',
              fontSize: 15,
              fontWeight: 720,
              transform: `translateY(${interpolate(success, [0, 1], [-10, 0])}px) scale(${interpolate(success, [0, 1], [.94, 1])})`,
              opacity: success,
              boxShadow: '0 12px 28px rgba(0,0,0,.28)',
            }}
          >
            <span style={{fontSize: 17}}>✓</span> Cookies received · Authenticated
          </div>
        )}
      </div>
    </div>
  );
};

const FlowStep = ({label, active, complete}: {label: string; active: boolean; complete: boolean}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
    <span
      style={{
        width: 10,
        height: 10,
        borderRadius: '50%',
        background: complete ? '#54dc89' : active ? ORANGE : 'rgba(255,255,255,.2)',
        boxShadow: active ? '0 0 16px rgba(255,69,0,.85)' : 'none',
      }}
    />
    <span
      style={{
        color: complete || active ? 'rgba(255,255,255,.86)' : 'rgba(255,255,255,.33)',
        fontSize: 17,
        fontWeight: active ? 680 : 500,
      }}
    >
      {label}
    </span>
  </div>
);

export const AuthHandoff = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const entrance = spring({frame, fps, config: {damping: 200}, durationInFrames: 30});
  const headerOpacity = interpolate(frame, [0, 18], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const panelsY = interpolate(entrance, [0, 1], [22, 0]);
  const phoneComplete = frame >= REVEAL_FRAME;

  return (
    <AbsoluteFill
      style={{
        color: '#fff',
        fontFamily: 'Inter, -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif',
        overflow: 'hidden',
      }}
    >
      <GridBackground />

      <div style={{position: 'absolute', inset: '45px 105px 0'}}>
        <div
          style={{
            opacity: headerOpacity,
            transform: `translateY(${(1 - entrance) * -8}px)`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
          }}
        >
          <div style={{display: 'flex', alignItems: 'center', gap: 14}}>
            <BrowserbaseMark size={42} />
            <div>
              <div style={{fontSize: 18, fontWeight: 730, letterSpacing: -.2}}>Browserbase</div>
              <div style={{fontSize: 12, color: 'rgba(255,255,255,.42)', letterSpacing: 1.45, marginTop: 3}}>
                LIVE AUTH HANDOFF
              </div>
            </div>
          </div>
        </div>

        <div style={{opacity: headerOpacity, marginTop: 27}}>
          <div style={{fontSize: 54, lineHeight: 1.03, fontWeight: 780, letterSpacing: -2.4}}>
            Authenticate on iPhone. <span style={{color: '#ff6a33'}}>Continue in Browserbase.</span>
          </div>
        </div>

        <div
          style={{
            marginTop: 30,
            transform: `translateY(${panelsY}px)`,
            opacity: entrance,
            display: 'grid',
            gridTemplateColumns: '420px 1120px',
            columnGap: 56,
            justifyContent: 'center',
          }}
        >
          <div>
            <Label number="1">Authenticate on iPhone</Label>
            <div style={{height: 12}} />
            <div style={{height: 630, display: 'flex', justifyContent: 'center', alignItems: 'center'}}>
              <DeviceFrame>
                <Video
                  src={staticFile('iphone-h264.mp4')}
                  muted
                  style={{width: '100%', height: '100%', objectFit: 'cover'}}
                />
              </DeviceFrame>
            </div>
          </div>

          <div>
            <Label number="2">Continue in Browserbase</Label>
            <div style={{height: 12}} />
            <BrowserPanel />
          </div>
        </div>

        <div
          style={{
            position: 'absolute',
            top: 968,
            left: '50%',
            transform: 'translateX(-50%)',
            display: 'flex',
            alignItems: 'center',
            gap: 19,
            padding: '13px 20px',
            borderRadius: 999,
            background: 'rgba(255,255,255,.045)',
            border: '1px solid rgba(255,255,255,.075)',
            whiteSpace: 'nowrap',
          }}
        >
          <FlowStep label="Open secure card" active={frame < 55} complete={frame >= 55} />
          <span style={{color: 'rgba(255,255,255,.16)'}}>→</span>
          <FlowStep
            label="Authenticate"
            active={frame >= 55 && !phoneComplete}
            complete={phoneComplete}
          />
          <span style={{color: 'rgba(255,255,255,.16)'}}>→</span>
          <FlowStep label="Cookie sync" active={phoneComplete} complete={false} />
        </div>
      </div>
    </AbsoluteFill>
  );
};
