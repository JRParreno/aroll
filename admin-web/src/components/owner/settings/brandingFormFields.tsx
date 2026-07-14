import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { BusinessBrandingSettings } from "@/lib/api";

export function ImageUploadField({
  label,
  value,
  onChange,
  helper,
}: {
  label: string;
  value: string | null;
  onChange: (value: string | null) => void;
  helper?: string;
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
        <div className="flex h-24 items-center justify-center overflow-hidden rounded-xl bg-white">
          {value ? (
            <img className="h-full w-full object-contain p-2" src={value} alt={label} />
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

export function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="flex items-center gap-3">
        <input
          className="h-10 w-12 rounded border"
          type="color"
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
        <Input value={value} onChange={(event) => onChange(event.target.value)} />
      </div>
    </div>
  );
}

export function BusinessLogoAndThemeFields({
  branding,
  onChange,
}: {
  branding: BusinessBrandingSettings;
  onChange: (branding: BusinessBrandingSettings) => void;
}) {
  return (
    <div className="space-y-6">
      <ImageUploadField
        label="Business Logo"
        helper="Shown in the owner sidebar and employee mobile app."
        value={branding.logo_url}
        onChange={(logo_url) => onChange({ ...branding, logo_url })}
      />
      <div className="grid gap-4 md:grid-cols-2">
        <ColorField
          label="Primary / Brand Color"
          value={branding.theme.primary_color}
          onChange={(primary_color) =>
            onChange({
              ...branding,
              theme: { ...branding.theme, primary_color },
            })
          }
        />
        <ColorField
          label="Secondary Color"
          value={branding.theme.secondary_color}
          onChange={(secondary_color) =>
            onChange({
              ...branding,
              theme: { ...branding.theme, secondary_color },
            })
          }
        />
        <ColorField
          label="Sidebar Color"
          value={branding.theme.sidebar_color}
          onChange={(sidebar_color) =>
            onChange({
              ...branding,
              theme: { ...branding.theme, sidebar_color },
            })
          }
        />
        <ColorField
          label="Button Color"
          value={branding.theme.button_color}
          onChange={(button_color) =>
            onChange({
              ...branding,
              theme: { ...branding.theme, button_color },
            })
          }
        />
      </div>
    </div>
  );
}
