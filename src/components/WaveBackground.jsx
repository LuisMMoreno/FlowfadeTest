import React, { useRef, useEffect, useCallback, useState } from 'react';

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function rgba(rgb, alpha) {
  return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha})`;
}

/**
 * Fondo de ondas orgánicas reactivas al ritmo.
 * Renderiza en Canvas 2D con optimización GPU.
 */
export const WaveBackground = ({
  bassLevel = 0,
  midLevel = 0,
  primaryRgb = [29, 185, 84],
  secondaryRgb = [25, 20, 20],
  isPlaying = false
}) => {
  const canvasRef = useRef(null);
  const animationRef = useRef(null);
  const timeRef = useRef(0);
  const lastFrameRef = useRef(0);
  const smoothBassRef = useRef(0);
  const smoothMidRef = useRef(0);
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false);

  const waveConfigsRef = useRef([
    { frequency: 0.010, amplitude: 40, speed: 0.46, phase: 0, verticalPos: 0.34, alpha: 0.12, lineAlpha: 0.26 },
    { frequency: 0.007, amplitude: 54, speed: 0.30, phase: Math.PI / 3, verticalPos: 0.46, alpha: 0.11, lineAlpha: 0.18 },
    { frequency: 0.012, amplitude: 36, speed: 0.58, phase: Math.PI / 1.7, verticalPos: 0.58, alpha: 0.10, lineAlpha: 0.22 },
    { frequency: 0.006, amplitude: 62, speed: 0.22, phase: Math.PI * 1.14, verticalPos: 0.70, alpha: 0.08, lineAlpha: 0.14 }
  ]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => setPrefersReducedMotion(media.matches);
    update();
    media.addEventListener?.('change', update);
    return () => media.removeEventListener?.('change', update);
  }, []);

  const drawWave = useCallback((ctx, width, height, time, bass, mid, wave, index, stepSize) => {
    const modulation = 0.72 + bass * 1.3 + mid * 0.55;
    const centerY = height * wave.verticalPos;
    const amplitude = wave.amplitude * modulation;
    const speed = wave.speed * (1 + mid * 0.34);

    ctx.beginPath();
    ctx.moveTo(0, height);

    for (let x = 0; x <= width + stepSize; x += stepSize) {
      const normalizedX = x / width;
      const curve =
        Math.sin(x * wave.frequency + time * speed + wave.phase) * amplitude * 0.52 +
        Math.sin(x * wave.frequency * 2.4 + time * speed * 1.2 + wave.phase * 0.72) * amplitude * 0.22 +
        Math.sin(x * wave.frequency * 0.6 + time * speed * 0.65 + wave.phase * 1.35) * amplitude * 0.16 +
        Math.cos(normalizedX * Math.PI * 4 + time * 0.18 + index) * 10 * bass;

      ctx.lineTo(x, centerY + curve);
    }

    ctx.lineTo(width, height);
    ctx.closePath();

    const gradient = ctx.createLinearGradient(0, centerY - amplitude, 0, height);
    const waveColor = index % 2 === 0 ? primaryRgb : secondaryRgb;
    const alphaTop = wave.alpha + bass * 0.04;
    const alphaMid = wave.alpha * 0.8 + mid * 0.03;

    gradient.addColorStop(0, rgba(waveColor, alphaTop));
    gradient.addColorStop(0.6, rgba(waveColor, alphaMid));
    gradient.addColorStop(1, rgba(waveColor, 0.015));
    ctx.fillStyle = gradient;
    ctx.fill();

    ctx.beginPath();
    for (let x = 0; x <= width + stepSize; x += stepSize) {
      const normalizedX = x / width;
      const curve =
        Math.sin(x * wave.frequency + time * speed + wave.phase) * amplitude * 0.52 +
        Math.sin(x * wave.frequency * 2.4 + time * speed * 1.2 + wave.phase * 0.72) * amplitude * 0.22 +
        Math.sin(x * wave.frequency * 0.6 + time * speed * 0.65 + wave.phase * 1.35) * amplitude * 0.16 +
        Math.cos(normalizedX * Math.PI * 4 + time * 0.18 + index) * 10 * bass;

      if (x === 0) {
        ctx.moveTo(x, centerY + curve);
      } else {
        ctx.lineTo(x, centerY + curve);
      }
    }

    ctx.strokeStyle = rgba(waveColor, wave.lineAlpha + bass * 0.05);
    ctx.lineWidth = 1.15;
    ctx.stroke();
  }, [primaryRgb, secondaryRgb]);

  const draw = useCallback((timestamp) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (!width || !height) {
      animationRef.current = requestAnimationFrame(draw);
      return;
    }

    if (!lastFrameRef.current) lastFrameRef.current = timestamp;
    const delta = Math.min((timestamp - lastFrameRef.current) / 1000, 0.05);
    lastFrameRef.current = timestamp;

    if (isPlaying && !prefersReducedMotion) {
      timeRef.current += delta;
    }

    const lerpFactor = prefersReducedMotion ? 0.04 : 0.085;
    smoothBassRef.current += (bassLevel - smoothBassRef.current) * lerpFactor;
    smoothMidRef.current += (midLevel - smoothMidRef.current) * lerpFactor;

    const bass = clamp(smoothBassRef.current, 0, 1);
    const mid = clamp(smoothMidRef.current, 0, 1);
    const time = timeRef.current;
    const stepSize = width > 768 ? 4 : 3;

    ctx.clearRect(0, 0, width, height);

    const wash = ctx.createRadialGradient(width * 0.5, height * 0.25, 0, width * 0.5, height * 0.58, height * 0.8);
    wash.addColorStop(0, rgba(primaryRgb, 0.12 + bass * 0.06));
    wash.addColorStop(0.45, rgba(secondaryRgb, 0.07 + mid * 0.04));
    wash.addColorStop(1, 'rgba(2, 6, 16, 0)');
    ctx.fillStyle = wash;
    ctx.fillRect(0, 0, width, height);

    waveConfigsRef.current.forEach((wave, index) => {
      drawWave(ctx, width, height, time, bass, mid, wave, index, stepSize);
    });

    const orbRadius = 110 + bass * 55;
    const orbX = width * (0.22 + mid * 0.06);
    const orbY = height * (0.28 + bass * 0.03);
    const orb = ctx.createRadialGradient(orbX, orbY, 0, orbX, orbY, orbRadius);
    orb.addColorStop(0, rgba(primaryRgb, 0.16 + bass * 0.08));
    orb.addColorStop(1, rgba(primaryRgb, 0));
    ctx.fillStyle = orb;
    ctx.fillRect(0, 0, width, height);

    const orb2Radius = 140 + mid * 60;
    const orb2X = width * (0.78 - bass * 0.05);
    const orb2Y = height * 0.68;
    const orb2 = ctx.createRadialGradient(orb2X, orb2Y, 0, orb2X, orb2Y, orb2Radius);
    orb2.addColorStop(0, rgba(secondaryRgb, 0.11 + mid * 0.05));
    orb2.addColorStop(1, rgba(secondaryRgb, 0));
    ctx.fillStyle = orb2;
    ctx.fillRect(0, 0, width, height);

    animationRef.current = requestAnimationFrame(draw);
  }, [bassLevel, drawWave, isPlaying, midLevel, prefersReducedMotion, primaryRgb, secondaryRgb]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const handleResize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const rect = canvas.getBoundingClientRect();
      canvas.width = Math.max(1, Math.round(rect.width * dpr));
      canvas.height = Math.max(1, Math.round(rect.height * dpr));
      const ctx = canvas.getContext('2d');
      if (ctx) {
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      }
    };

    handleResize();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  useEffect(() => {
    animationRef.current = requestAnimationFrame(draw);

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [draw]);

  return (
    <canvas
      ref={canvasRef}
      className="gpu-accelerated"
      style={{
        position: 'absolute',
        inset: 0,
        width: '100%',
        height: '100%',
        pointerEvents: 'none',
        zIndex: 1,
        opacity: 0.96
      }}
      aria-hidden="true"
    />
  );
};
