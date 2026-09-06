import React, { useEffect, useRef, useState } from 'react';
import { Animated, Dimensions, Easing, Pressable, StyleSheet, View } from 'react-native';

// Pixel-art sprite frames. Each char = one pixel. '.' = transparent.
// Palette: o = outline, b = body, l = light belly, e = eye, k = cheek, w = white
const PALETTE: Record<string, string> = {
  o: '#3b2a3a',
  b: '#ffb347',
  l: '#ffe1a8',
  e: '#3b2a3a',
  k: '#ff7b9c',
  w: '#ffffff',
};

const FRAME_OPEN = [
  '....oooo....',
  '..oo.bb.oo..',
  '.obbbbbbbbo.',
  '.obbbbbbbbo.',
  'obbeobbbeobo',
  'obbwobbbwobo',
  'obbbbbbbbbbo',
  'obkbbbbbbkbo',
  'obbllllllbbo',
  '.obllllllbo.',
  '..oobbbboo..',
  '...o.oo.o...',
];

const FRAME_BLINK = FRAME_OPEN.map((row, i) =>
  i === 4 ? 'obboobbboobo' : i === 5 ? 'obbbbbbbbbbo' : row,
);

const PX = 4; // pixel size
const W = FRAME_OPEN[0].length * PX;
const H = FRAME_OPEN.length * PX;

function Sprite({ frame, flip }: { frame: string[]; flip: boolean }) {
  return (
    <View style={{ width: W, height: H, transform: [{ scaleX: flip ? -1 : 1 }] }}>
      {frame.map((row, y) =>
        row.split('').map((c, x) =>
          c === '.' ? null : (
            <View
              key={`${x}-${y}`}
              style={{
                position: 'absolute',
                left: x * PX,
                top: y * PX,
                width: PX,
                height: PX,
                backgroundColor: PALETTE[c],
              }}
            />
          ),
        ),
      )}
    </View>
  );
}

type Props = {
  /** X position the pet should walk to (e.g. center of the active tab). */
  targetX?: number;
  /** Distance from the bottom of the parent to the pet's feet. */
  bottom: number;
};

export default function Pet({ targetX, bottom }: Props) {
  const screenW = Dimensions.get('window').width;
  const x = useRef(new Animated.Value(screenW / 2 - W / 2)).current;
  const bounce = useRef(new Animated.Value(0)).current;
  const jump = useRef(new Animated.Value(0)).current;
  const [blink, setBlink] = useState(false);
  const [flip, setFlip] = useState(false);
  const curX = useRef(screenW / 2 - W / 2);

  useEffect(() => {
    const id = x.addListener(({ value }) => (curX.current = value));
    return () => x.removeListener(id);
  }, [x]);

  // idle bob
  useEffect(() => {
    Animated.loop(
      Animated.sequence([
        Animated.timing(bounce, { toValue: -3, duration: 350, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
        Animated.timing(bounce, { toValue: 0, duration: 350, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      ]),
    ).start();
  }, [bounce]);

  // blink
  useEffect(() => {
    let alive = true;
    const tick = () => {
      if (!alive) return;
      setTimeout(() => {
        if (!alive) return;
        setBlink(true);
        setTimeout(() => alive && setBlink(false), 120);
        tick();
      }, 1800 + Math.random() * 2500);
    };
    tick();
    return () => { alive = false; };
  }, []);

  const walkTo = (dest: number) => {
    const clamped = Math.max(4, Math.min(screenW - W - 4, dest));
    setFlip(clamped < curX.current);
    const dist = Math.abs(clamped - curX.current);
    Animated.timing(x, {
      toValue: clamped,
      duration: Math.max(250, dist * 3),
      easing: Easing.inOut(Easing.quad),
      useNativeDriver: true,
    }).start();
  };

  // walk to active tab
  useEffect(() => {
    if (targetX !== undefined) walkTo(targetX - W / 2);
  }, [targetX]);

  // random wandering when idle
  useEffect(() => {
    let alive = true;
    const wander = () => {
      if (!alive) return;
      setTimeout(() => {
        if (!alive) return;
        const drift = (Math.random() - 0.5) * 120;
        walkTo(curX.current + drift);
        wander();
      }, 3000 + Math.random() * 4000);
    };
    wander();
    return () => { alive = false; };
  }, []);

  const doJump = () => {
    Animated.sequence([
      Animated.timing(jump, { toValue: -22, duration: 160, easing: Easing.out(Easing.quad), useNativeDriver: true }),
      Animated.timing(jump, { toValue: 0, duration: 200, easing: Easing.bounce, useNativeDriver: true }),
    ]).start();
  };

  return (
    <Animated.View
      pointerEvents="box-none"
      style={[
        styles.wrap,
        { bottom, transform: [{ translateX: x }, { translateY: Animated.add(bounce, jump) }] },
      ]}
    >
      <Pressable onPress={doJump} hitSlop={8}>
        <Sprite frame={blink ? FRAME_BLINK : FRAME_OPEN} flip={flip} />
      </Pressable>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 0, zIndex: 100, elevation: 100 },
});
