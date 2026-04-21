import { useState, useEffect, useRef } from 'react';
import { ColorExtractionService } from '../services/ColorExtractionService';

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function rgbToHsl(r, g, b) {
  const nr = r / 255;
  const ng = g / 255;
  const nb = b / 255;
  const max = Math.max(nr, ng, nb);
  const min = Math.min(nr, ng, nb);
  let h = 0;
  let s = 0;
  const l = (max + min) / 2;

  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

    switch (max) {
      case nr:
        h = (ng - nb) / d + (ng < nb ? 6 : 0);
        break;
      case ng:
        h = (nb - nr) / d + 2;
        break;
      default:
        h = (nr - ng) / d + 4;
        break;
    }

    h /= 6;
  }

  return [h, s, l];
}

function hue2rgb(p, q, t) {
  let value = t;
  if (value < 0) value += 1;
  if (value > 1) value -= 1;
  if (value < 1 / 6) return p + (q - p) * 6 * value;
  if (value < 1 / 2) return q;
  if (value < 2 / 3) return p + (q - p) * (2 / 3 - value) * 6;
  return p;
}

function hslToRgb(h, s, l) {
  if (s === 0) {
    const gray = Math.round(l * 255);
    return [gray, gray, gray];
  }

  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;

  return [
    Math.round(hue2rgb(p, q, h + 1 / 3) * 255),
    Math.round(hue2rgb(p, q, h) * 255),
    Math.round(hue2rgb(p, q, h - 1 / 3) * 255)
  ];
}

function mixRgb(a, b, weight = 0.5) {
  return [
    Math.round(a[0] * (1 - weight) + b[0] * weight),
    Math.round(a[1] * (1 - weight) + b[1] * weight),
    Math.round(a[2] * (1 - weight) + b[2] * weight)
  ];
}

function rgbToCss(rgb, alpha) {
  if (typeof alpha === 'number') {
    return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha})`;
  }
  return `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`;
}

function polishRgb(rgb, { saturationBoost = 0.08, minLightness = 0.2, maxLightness = 0.46 } = {}) {
  const [h, s, l] = rgbToHsl(...rgb);
  return hslToRgb(
    h,
    clamp(s + saturationBoost, 0.18, 0.86),
    clamp(l, minLightness, maxLightness)
  );
}

function buildDerivedPalette(baseColors) {
  const primaryRgb = polishRgb(baseColors.primaryRgb, {
    saturationBoost: 0.06,
    minLightness: 0.26,
    maxLightness: 0.44
  });

  const secondaryRgb = polishRgb(
    mixRgb(baseColors.secondaryRgb, [12, 18, 32], 0.35),
    {
      saturationBoost: 0.03,
      minLightness: 0.14,
      maxLightness: 0.26
    }
  );

  const accentRgb = mixRgb(primaryRgb, [255, 255, 255], 0.12);
  const accentSoftRgb = mixRgb(primaryRgb, secondaryRgb, 0.3);
  const surfaceHighRgb = mixRgb(primaryRgb, [255, 255, 255], 0.18);
  const surfaceLowRgb = mixRgb(secondaryRgb, [4, 8, 18], 0.58);
  const textMutedRgb = mixRgb([255, 255, 255], secondaryRgb, 0.34);

  return {
    primary: rgbToCss(primaryRgb),
    secondary: rgbToCss(secondaryRgb),
    primaryRgb,
    secondaryRgb,
    accentColor: rgbToCss(accentRgb),
    accentSoft: rgbToCss(accentSoftRgb),
    mutedTextColor: rgbToCss(textMutedRgb, 0.82),
    glowColor: rgbToCss(accentRgb, 0.28),
    shadowColor: rgbToCss(mixRgb(primaryRgb, [0, 0, 0], 0.66), 0.44),
    gradient: `linear-gradient(135deg, ${rgbToCss(primaryRgb)} 0%, ${rgbToCss(secondaryRgb)} 100%)`,
    ambientGradient: `
      radial-gradient(circle at 50% -8%, ${rgbToCss(accentRgb, 0.34)} 0%, rgba(0, 0, 0, 0) 34%),
      radial-gradient(circle at 14% 18%, ${rgbToCss(primaryRgb, 0.18)} 0%, rgba(0, 0, 0, 0) 38%),
      linear-gradient(180deg, ${rgbToCss(surfaceHighRgb, 0.28)} 0%, ${rgbToCss(surfaceLowRgb, 0.9)} 58%, rgba(3, 7, 16, 0.98) 100%)
    `,
    surfaceGradient: `linear-gradient(180deg, ${rgbToCss(surfaceHighRgb, 0.2)} 0%, ${rgbToCss(surfaceLowRgb, 0.78)} 100%)`
  };
}

function applyRootVariables(result) {
  const root = document.documentElement;
  root.style.setProperty('--current-primary', result.primary);
  root.style.setProperty('--current-secondary', result.secondary);
  root.style.setProperty('--current-gradient', result.gradient);
  root.style.setProperty('--current-primary-r', result.primaryRgb[0]);
  root.style.setProperty('--current-primary-g', result.primaryRgb[1]);
  root.style.setProperty('--current-primary-b', result.primaryRgb[2]);
  root.style.setProperty('--current-secondary-r', result.secondaryRgb[0]);
  root.style.setProperty('--current-secondary-g', result.secondaryRgb[1]);
  root.style.setProperty('--current-secondary-b', result.secondaryRgb[2]);
}

/**
 * Hook que extrae los colores dominantes de la carátula del álbum actual
 * y los aplica como variables CSS dinámicas en :root.
 */
export function useAlbumColors(coverUrl) {
  const [colors, setColors] = useState(() => buildDerivedPalette(ColorExtractionService.getDefaultColors()));
  const [isLoading, setIsLoading] = useState(false);
  const lastCoverRef = useRef(null);

  useEffect(() => {
    if (coverUrl === lastCoverRef.current) return;
    lastCoverRef.current = coverUrl;

    let cancelled = false;
    setIsLoading(true);

    ColorExtractionService.extractColors(coverUrl)
      .then((result) => {
        if (cancelled) return;

        const derived = buildDerivedPalette(result);
        setColors(derived);
        setIsLoading(false);
        applyRootVariables(derived);
      })
      .catch(() => {
        if (cancelled) return;

        const fallback = buildDerivedPalette(ColorExtractionService.getDefaultColors());
        setColors(fallback);
        setIsLoading(false);
        applyRootVariables(fallback);
      });

    return () => {
      cancelled = true;
    };
  }, [coverUrl]);

  return {
    primaryColor: colors.primary,
    secondaryColor: colors.secondary,
    primaryRgb: colors.primaryRgb,
    secondaryRgb: colors.secondaryRgb,
    gradient: colors.gradient,
    ambientGradient: colors.ambientGradient,
    surfaceGradient: colors.surfaceGradient,
    accentColor: colors.accentColor,
    accentSoft: colors.accentSoft,
    mutedTextColor: colors.mutedTextColor,
    glowColor: colors.glowColor,
    shadowColor: colors.shadowColor,
    isLoading
  };
}
