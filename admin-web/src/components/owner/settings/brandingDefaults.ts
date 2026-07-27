import type { BusinessBrandingSettings, BusinessThemeSettings } from "@/lib/api";
import {
  defaultScheduleColors,
  defaultScheduleDisplay,
} from "@/components/owner/schedule/scheduleThemeDefaults";

export const defaultBusinessTheme: BusinessThemeSettings = {
  primary_color: "#1E3A5F",
  secondary_color: "#284B73",
  sidebar_color: "#1E3A5F",
  accent_color: "#3B82F6",
  button_color: "#1E3A5F",
  card_style: "soft",
  font_size: "comfortable",
  color_mode: "light",
  layout_density: "rounded",
  schedule_colors: defaultScheduleColors,
  schedule_display: defaultScheduleDisplay,
};

export const defaultBusinessBranding: BusinessBrandingSettings = {
  logo_url: null,
  owner_profile_image_url: null,
  display_image_url: null,
  theme: defaultBusinessTheme,
};

export function businessBrandingForSave(
  branding: BusinessBrandingSettings
): BusinessBrandingSettings {
  return {
    logo_url: branding.logo_url,
    owner_profile_image_url: branding.owner_profile_image_url,
    display_image_url: branding.logo_url,
    theme: branding.theme,
  };
}
