import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import type { BusinessBrandingSettings, BusinessThemeSettings } from "@/lib/api";
import { cn } from "@/lib/utils";
import {
  BRAND_THEME_GROUPS,
  BRAND_THEMES,
  brandThemeSwatches,
  findBrandTheme,
  type BrandThemeColors,
} from "@/components/owner/settings/brandThemes";

export function ImageUploadField({
  label,
  value,
  onChange,
  helper,
  circularPreview = false,
}: {
  label: string;
  value: string | null;
  onChange: (value: string | null) => void;
  helper?: string;
  circularPreview?: boolean;
}) {
  function handleFile(file: File | null) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => onChange(String(reader.result));
    reader.readAsDataURL(file);
  }

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      {helper ? (
        <p className="text-xs text-muted-foreground">{helper}</p>
      ) : null}
      <div className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
        <div
          className={`flex items-center justify-center overflow-hidden bg-white ${
            circularPreview
              ? "mx-auto h-24 w-24 rounded-full ring-1 ring-slate-200"
              : "h-24 rounded-xl"
          }`}
        >
          {value ? (
            <img
              className={`h-full w-full ${
                circularPreview ? "object-cover" : "object-contain p-2"
              }`}
              src={value}
              alt={label}
            />
          ) : (
            <span className="text-xs text-muted-foreground">No image</span>
          )}
        </div>
        <div className="mt-3 flex gap-2">
          <label className="inline-flex cursor-pointer rounded-md border px-3 py-2 text-xs font-medium">
            Upload
            <input
              className="hidden"
              type="file"
              accept="image/*"
              onChange={(event) => handleFile(event.target.files?.[0] ?? null)}
            />
          </label>
          {value ? (
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => onChange(null)}
            >
              Remove
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function applyBrandColors(
  branding: BusinessBrandingSettings,
  colors: BrandThemeColors
): BusinessBrandingSettings {
  return {
    ...branding,
    theme: {
      ...branding.theme,
      ...colors,
    },
  };
}

function ThemeChoice({
  name,
  description,
  swatches,
  selected,
  onSelect,
}: {
  name: string;
  description: string;
  swatches: string[];
  selected: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      onClick={onSelect}
      className={cn(
        "flex h-full flex-col rounded-xl border bg-white p-2.5 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--owner-navy)]",
        selected
          ? "border-[var(--owner-navy)] shadow-[0_1px_2px_rgba(15,23,42,0.06)]"
          : "border-slate-200 hover:border-slate-300 hover:bg-slate-50"
      )}
    >
      <span className="text-sm font-semibold text-[#111827]">{name}</span>
      <span className="mt-2 flex h-6 overflow-hidden rounded-md border border-slate-200/80">
        {swatches.map((color, index) => (
          <span
            key={`${name}-${index}`}
            className="min-w-0 flex-1"
            style={{ backgroundColor: color }}
          />
        ))}
      </span>
      <span className="mt-1.5 line-clamp-2 text-xs leading-4 text-[#6B7280]">{description}</span>
      <span className="mt-2 flex items-center gap-1 text-xs font-semibold text-[var(--owner-navy)]">
        {selected ? (
          <>
            <Check className="h-3.5 w-3.5" aria-hidden="true" />
            Selected
          </>
        ) : (
          <span className="text-[#9CA3AF]">Choose</span>
        )}
      </span>
    </button>
  );
}

function BrandPreview({
  businessName,
  logoUrl,
  surface,
  colors,
}: {
  businessName?: string;
  logoUrl: string | null;
  surface: string;
  colors: BrandThemeColors;
}) {
  return (
    <div
      className="overflow-hidden rounded-xl border border-slate-200"
      style={{ backgroundColor: surface }}
    >
      <div className="flex min-h-[148px]">
        <div
          className="flex w-[4.5rem] shrink-0 flex-col gap-2 px-2 py-3"
          style={{ backgroundColor: colors.sidebar_color }}
        >
          {logoUrl ? (
            <img
              src={logoUrl}
              alt=""
              className="mx-auto h-8 w-8 rounded-full object-cover ring-1 ring-white/30"
            />
          ) : (
            <span className="mx-auto flex h-8 w-8 items-center justify-center rounded-full bg-white/15 text-xs font-semibold text-white">
              {(businessName ?? "A").slice(0, 1).toUpperCase()}
            </span>
          )}
          <span className="h-2 rounded-full bg-white/25" />
          <span
            className="h-2 rounded-full"
            style={{ backgroundColor: colors.secondary_color }}
          />
        </div>
        <div className="min-w-0 flex-1 p-3">
          <p className="truncate text-sm font-semibold text-[#111827]">
            {businessName?.trim() || "Your business"}
          </p>
          <p className="text-xs text-[#6B7280]">Welcome back</p>
          <div className="mt-3 grid grid-cols-2 gap-2">
            {["Attendance", "Payroll"].map((label) => (
              <div
                key={label}
                className="rounded-lg border border-white/80 bg-white px-2 py-2"
              >
                <p
                  className="truncate text-xs font-semibold"
                  style={{ color: colors.primary_color }}
                >
                  {label}
                </p>
              </div>
            ))}
          </div>
          <span
            className="mt-3 inline-flex rounded-md px-2.5 py-1 text-xs font-semibold text-white"
            style={{ backgroundColor: colors.button_color }}
          >
            Open
          </span>
        </div>
      </div>
    </div>
  );
}

export function BusinessLogoAndThemeFields({
  branding,
  savedTheme,
  businessName,
  onChange,
}: {
  branding: BusinessBrandingSettings;
  savedTheme?: BusinessThemeSettings;
  businessName?: string;
  onChange: (branding: BusinessBrandingSettings) => void;
}) {
  const selectedTheme = findBrandTheme(branding.theme);
  const savedIsCurated = savedTheme ? Boolean(findBrandTheme(savedTheme)) : true;
  const previewSurface = selectedTheme?.previewSurface ?? "#F4F6F8";
  const customSelected = !selectedTheme;

  return (
    <div className="space-y-6">
      <section className="space-y-3">
        <div>
          <h3 className="text-sm font-semibold text-[#111827]">Brand identity</h3>
          <p className="mt-1 text-sm text-[#6B7280]">
            Your logo appears in the owner portal and employee app.
          </p>
        </div>
        <ImageUploadField
          label="Logo"
          helper="Upload or replace the current business logo."
          value={branding.logo_url}
          onChange={(logo_url) => onChange({ ...branding, logo_url })}
          circularPreview
        />
      </section>

      <section className="space-y-3 border-t border-slate-200 pt-5">
        <div>
          <h3 className="text-sm font-semibold text-[#111827]">
            Choose your brand style
          </h3>
          <p className="mt-1 max-w-2xl text-sm leading-6 text-[#6B7280]">
            Select a professionally coordinated color theme. Each theme is
            designed to keep your Owner and Employee experience clean, readable,
            and visually balanced.
          </p>
        </div>
        <div role="radiogroup" aria-label="Color theme" className="space-y-4">
          {BRAND_THEME_GROUPS.map((group) => (
            <div key={group}>
              <p className="mb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[#6B7280]">
                {group}
              </p>
              <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 xl:grid-cols-4">
                {BRAND_THEMES.filter((theme) => theme.group === group).map(
                  (theme) => (
                    <ThemeChoice
                      key={theme.id}
                      name={theme.name}
                      description={theme.description}
                      swatches={brandThemeSwatches(
                        theme.colors,
                        theme.previewSurface
                      )}
                      selected={selectedTheme?.id === theme.id}
                      onSelect={() =>
                        onChange(applyBrandColors(branding, theme.colors))
                      }
                    />
                  )
                )}
              </div>
            </div>
          ))}
          {!savedIsCurated && savedTheme ? (
            <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 xl:grid-cols-4">
              <ThemeChoice
                name="Current theme"
                description="Saved colors stay until you choose a coordinated theme."
                swatches={brandThemeSwatches(savedTheme, "#F4F6F8")}
                selected={customSelected}
                onSelect={() => onChange(applyBrandColors(branding, savedTheme))}
              />
            </div>
          ) : null}
        </div>
      </section>

      <section className="space-y-3 border-t border-slate-200 pt-5">
        <h3 className="text-sm font-semibold text-[#111827]">Preview</h3>
        <BrandPreview
          businessName={businessName}
          logoUrl={branding.logo_url}
          surface={previewSurface}
          colors={branding.theme}
        />
      </section>
    </div>
  );
}
