/**
 * Run: npx --yes tsx --test src/components/owner/settings/brandThemes.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { defaultBusinessTheme } from "./brandingDefaults.ts";
import {
  BRAND_COLOR_OPTIONS,
  BRAND_THEMES,
  FEATURED_BRAND_THEMES,
  PLUM_BRAND_THEME,
  SYSTEM_BRAND_THEME,
  SYSTEM_THEME_SURFACE,
  findBrandTheme,
  orderedBrandThemes,
} from "./brandThemes.ts";

describe("owner brand themes", () => {
  it("lists System Theme first, then the ready-made themes", () => {
    const names = orderedBrandThemes().map((theme) => theme.name);
    assert.equal(names[0], "System Theme (Default)");
    assert.equal(names[1], "Soft Blue");
    assert.equal(FEATURED_BRAND_THEMES.length, 1);
    assert.equal(FEATURED_BRAND_THEMES[0].id, "system");
    const plum = BRAND_THEMES.find((theme) => theme.id === "aroll-signature");
    assert.equal(plum?.name, "Plum");
    assert.equal(plum?.group, "Warm");
    assert.equal(
      BRAND_THEMES.filter((theme) => theme.group === "Warm").at(-1)?.name,
      "Plum"
    );
  });

  it("uses the login page background and the saved default navy", () => {
    assert.equal(SYSTEM_THEME_SURFACE, "#F4F6F8");
    assert.equal(SYSTEM_BRAND_THEME.previewSurface, "#F4F6F8");
    assert.equal(
      SYSTEM_BRAND_THEME.colors.primary_color,
      defaultBusinessTheme.primary_color
    );
    assert.equal(SYSTEM_BRAND_THEME.colors.primary_color, "#1E3A5F");
    assert.equal(SYSTEM_BRAND_THEME.colors.sidebar_color, "#1E3A5F");
    assert.equal(SYSTEM_BRAND_THEME.colors.button_color, "#1E3A5F");
    assert.equal(SYSTEM_BRAND_THEME.colors.secondary_color, "#284B73");
    assert.equal(SYSTEM_BRAND_THEME.colors.accent_color, "#3B82F6");
    assert.equal(findBrandTheme(defaultBusinessTheme)?.id, "system");
  });

  it("keeps the plum palette and its saved color match", () => {
    assert.equal(PLUM_BRAND_THEME.name, "Plum");
    assert.equal(PLUM_BRAND_THEME.id, "aroll-signature");
    assert.equal(PLUM_BRAND_THEME.group, "Warm");
    assert.equal(PLUM_BRAND_THEME.colors.sidebar_color, "#3C275C");
    assert.equal(PLUM_BRAND_THEME.colors.primary_color, "#4C366E");
    assert.equal(PLUM_BRAND_THEME.colors.button_color, "#4A3168");
    assert.equal(PLUM_BRAND_THEME.colors.accent_color, "#8C6E16");
    assert.equal(PLUM_BRAND_THEME.colors.secondary_color, "#7A3142");
    assert.equal(findBrandTheme({
      ...defaultBusinessTheme,
      ...PLUM_BRAND_THEME.colors,
    })?.id, "aroll-signature");
    assert.equal(
      orderedBrandThemes().filter((theme) => theme.name === "Plum").length,
      1
    );
  });

  it("keeps a custom palette unmatched so saved colors are not treated as a preset", () => {
    const custom = findBrandTheme({
      ...defaultBusinessTheme,
      primary_color: "#112233",
    });
    assert.equal(custom, undefined);
  });

  it("explains only the colors the theme model already stores", () => {
    assert.deepEqual(
      BRAND_COLOR_OPTIONS.map((option) => option.key),
      [
        "primary_color",
        "secondary_color",
        "accent_color",
        "sidebar_color",
        "button_color",
      ]
    );
    assert.match(BRAND_COLOR_OPTIONS[0].effect, /Headings/);
    assert.match(BRAND_COLOR_OPTIONS[2].effect, /does not change the page background/);
    assert.match(BRAND_COLOR_OPTIONS[3].effect, /sidebar/i);
  });

  it("keeps the existing Soft Blue theme", () => {
    const softBlue = BRAND_THEMES.find((theme) => theme.id === "soft-blue");
    assert.equal(softBlue?.colors.primary_color, "#3D6280");
    assert.equal(softBlue?.colors.sidebar_color, "#35556F");
  });
});
