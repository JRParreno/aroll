import type { BusinessThemeSettings } from "@/lib/api";

/** Colors written into the existing branding theme. Non-color settings stay untouched. */
export type BrandThemeColors = Pick<
  BusinessThemeSettings,
  | "primary_color"
  | "secondary_color"
  | "sidebar_color"
  | "accent_color"
  | "button_color"
>;

export type BrandThemeGroup = "Calm" | "Warm" | "Fresh";

export type BrandTheme = {
  id: string;
  name: string;
  description: string;
  group: BrandThemeGroup;
  /** Settings preview surface only. Not saved. */
  previewSurface: string;
  colors: BrandThemeColors;
};

export const BRAND_THEME_GROUPS: BrandThemeGroup[] = ["Calm", "Warm", "Fresh"];

export const BRAND_THEMES: BrandTheme[] = [
  {
    id: "soft-blue",
    name: "Soft Blue",
    description: "Calm, clean, professional",
    group: "Calm",
    previewSurface: "#E7F0F6",
    colors: {
      sidebar_color: "#35556F",
      primary_color: "#3D6280",
      button_color: "#3A5C78",
      secondary_color: "#4A7090",
      accent_color: "#5E86A3",
    },
  },
  {
    id: "sage",
    name: "Sage",
    description: "Soft botanical green",
    group: "Calm",
    previewSurface: "#E7F0EA",
    colors: {
      sidebar_color: "#3E5348",
      primary_color: "#466053",
      button_color: "#42604F",
      secondary_color: "#547062",
      accent_color: "#5E7A68",
    },
  },
  {
    id: "lavender",
    name: "Lavender",
    description: "Quiet and restrained",
    group: "Calm",
    previewSurface: "#EEEAF4",
    colors: {
      sidebar_color: "#4A4568",
      primary_color: "#554F78",
      button_color: "#514B72",
      secondary_color: "#655F88",
      accent_color: "#746C96",
    },
  },
  {
    id: "peach",
    name: "Peach",
    description: "Warm and gentle",
    group: "Warm",
    previewSurface: "#F8EFEA",
    colors: {
      sidebar_color: "#6A4A3C",
      primary_color: "#745445",
      button_color: "#6E4E40",
      secondary_color: "#806052",
      accent_color: "#8C6A58",
    },
  },
  {
    id: "blush",
    name: "Blush",
    description: "Soft rose with neutral depth",
    group: "Warm",
    previewSurface: "#F8EEF1",
    colors: {
      sidebar_color: "#6A4552",
      primary_color: "#754C5A",
      button_color: "#6F4856",
      secondary_color: "#865C6A",
      accent_color: "#946274",
    },
  },
  {
    id: "sky",
    name: "Sky",
    description: "Cool and airy",
    group: "Calm",
    previewSurface: "#E8F3F6",
    colors: {
      sidebar_color: "#3A5568",
      primary_color: "#426074",
      button_color: "#3E5C70",
      secondary_color: "#4E7084",
      accent_color: "#5C8498",
    },
  },
  {
    id: "sand",
    name: "Sand",
    description: "Warm beige, muted accent",
    group: "Warm",
    previewSurface: "#F6F1EA",
    colors: {
      sidebar_color: "#5C5146",
      primary_color: "#665A4E",
      button_color: "#615548",
      secondary_color: "#74685C",
      accent_color: "#7E7264",
    },
  },
  {
    id: "mint",
    name: "Mint",
    description: "Fresh and balanced",
    group: "Calm",
    previewSurface: "#E8F6F1",
    colors: {
      sidebar_color: "#3A554C",
      primary_color: "#426056",
      button_color: "#3E5C52",
      secondary_color: "#4E7066",
      accent_color: "#5C8478",
    },
  },
  {
    id: "cream",
    name: "Cream",
    description: "Soft warm neutral",
    group: "Warm",
    previewSurface: "#F7F3EC",
    colors: {
      sidebar_color: "#5A5348",
      primary_color: "#645C50",
      button_color: "#5F584C",
      secondary_color: "#726A5E",
      accent_color: "#7C7466",
    },
  },
  {
    id: "soft-coral",
    name: "Soft Coral",
    description: "Muted warm coral",
    group: "Warm",
    previewSurface: "#F8EEEE",
    colors: {
      sidebar_color: "#6A4548",
      primary_color: "#754E50",
      button_color: "#6F494C",
      secondary_color: "#855E60",
      accent_color: "#94686A",
    },
  },
  {
    id: "aqua",
    name: "Aqua",
    description: "Clear and light",
    group: "Fresh",
    previewSurface: "#E7F4F5",
    colors: {
      sidebar_color: "#355E64",
      primary_color: "#3D6A70",
      button_color: "#39646A",
      secondary_color: "#456F76",
      accent_color: "#5A8890",
    },
  },
  {
    id: "soft-teal",
    name: "Soft Teal",
    description: "Cool and steady",
    group: "Fresh",
    previewSurface: "#E6F3F2",
    colors: {
      sidebar_color: "#2F5558",
      primary_color: "#386266",
      button_color: "#345E62",
      secondary_color: "#467276",
      accent_color: "#548488",
    },
  },
  {
    id: "pistachio",
    name: "Pistachio",
    description: "Light green, grounded",
    group: "Fresh",
    previewSurface: "#F0F4EA",
    colors: {
      sidebar_color: "#4A5540",
      primary_color: "#54624A",
      button_color: "#4F5C46",
      secondary_color: "#627058",
      accent_color: "#6E7C62",
    },
  },
  {
    id: "soft-lilac",
    name: "Soft Lilac",
    description: "Gentle cool violet",
    group: "Fresh",
    previewSurface: "#F3EEF6",
    colors: {
      sidebar_color: "#554860",
      primary_color: "#62546E",
      button_color: "#5C4E68",
      secondary_color: "#72647E",
      accent_color: "#80728C",
    },
  },
];

const THEME_COLOR_KEYS = [
  "primary_color",
  "secondary_color",
  "sidebar_color",
  "accent_color",
  "button_color",
] as const;

export function normalizeBrandHex(value: string) {
  const raw = value.trim().replace(/^#/, "");
  if (/^[0-9a-fA-F]{3}$/.test(raw)) {
    return `#${raw
      .split("")
      .map((char) => `${char}${char}`)
      .join("")
      .toUpperCase()}`;
  }
  if (/^[0-9a-fA-F]{6}$/.test(raw)) {
    return `#${raw.toUpperCase()}`;
  }
  return value.trim().toUpperCase();
}

export function brandThemesMatch(
  theme: BusinessThemeSettings,
  colors: BrandThemeColors
) {
  return THEME_COLOR_KEYS.every(
    (key) => normalizeBrandHex(theme[key]) === normalizeBrandHex(colors[key])
  );
}

export function findBrandTheme(theme: BusinessThemeSettings) {
  return BRAND_THEMES.find((item) => brandThemesMatch(theme, item.colors));
}

export function brandThemeSwatches(colors: BrandThemeColors, surface: string) {
  return [surface, colors.accent_color, colors.secondary_color, colors.sidebar_color];
}
