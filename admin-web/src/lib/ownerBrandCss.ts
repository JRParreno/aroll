import type { BusinessThemeSettings } from "@/lib/api";

const OWNER_BRAND_CSS_VARS = [
  "--owner-navy",
  "--owner-button",
  "--owner-navy-soft",
  "--owner-accent",
  "--owner-sidebar",
  "--owner-well",
  "--owner-primary-hsl",
  "--owner-ring-hsl",
  "--primary",
  "--primary-foreground",
  "--ring",
] as const;

function normalizeBrandHex(value: string | undefined, fallback: string): string {
  const raw = (value || "").trim();
  const hex = raw.startsWith("#") ? raw : raw ? `#${raw}` : fallback;
  if (/^#[0-9a-fA-F]{6}$/.test(hex)) return hex;
  if (/^#[0-9a-fA-F]{3}$/.test(hex)) {
    const [, r, g, b] = hex;
    return `#${r}${r}${g}${g}${b}${b}`;
  }
  return fallback;
}

function hexToHslChannels(hex: string): string {
  const n = Number.parseInt(hex.slice(1), 16);
  const r = ((n >> 16) & 255) / 255;
  const g = ((n >> 8) & 255) / 255;
  const b = (n & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return `0 0% ${Math.round(l * 100)}%`;
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h = 0;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return `${Math.round((h / 6) * 360)} ${Math.round(s * 100)}% ${Math.round(l * 100)}%`;
}

/** Writes the saved business theme onto the document so every owner route can use it. */
export function applyOwnerBrandCss(theme: BusinessThemeSettings | undefined) {
  const primary = normalizeBrandHex(theme?.primary_color, "#1E3A5F");
  const secondary = normalizeBrandHex(theme?.secondary_color, "#284B73");
  const button = normalizeBrandHex(theme?.button_color, "#1E3A5F");
  const accent = normalizeBrandHex(theme?.accent_color, "#3B82F6");
  const sidebar = normalizeBrandHex(theme?.sidebar_color, "#1E3A5F");
  const buttonHsl =
    button.toLowerCase() === "#1e3a5f" ? "213 52% 25%" : hexToHslChannels(button);
  const ringHsl =
    primary.toLowerCase() === "#1e3a5f" ? "213 45% 32%" : hexToHslChannels(primary);
  const well =
    primary.toLowerCase() === "#1e3a5f"
      ? "#e7eef5"
      : `color-mix(in srgb, ${primary} 12%, white)`;
  const root = document.documentElement;
  const vars: Record<string, string> = {
    "--owner-navy": primary,
    "--owner-button": button,
    "--owner-navy-soft": secondary,
    "--owner-accent": accent,
    "--owner-sidebar": sidebar,
    "--owner-well": well,
    "--owner-primary-hsl": buttonHsl,
    "--owner-ring-hsl": ringHsl,
    "--primary": buttonHsl,
    "--primary-foreground": "0 0% 100%",
    "--ring": ringHsl,
  };
  for (const [name, value] of Object.entries(vars)) {
    root.style.setProperty(name, value);
  }
}

export function clearOwnerBrandCss() {
  const root = document.documentElement;
  for (const name of OWNER_BRAND_CSS_VARS) {
    root.style.removeProperty(name);
  }
}
