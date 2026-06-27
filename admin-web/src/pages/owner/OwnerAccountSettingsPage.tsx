import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  changePassword,
  type BusinessBrandingSettings,
  getAccountSettings,
  updateAccountSettings,
} from "@/lib/api";
import { ME_QUERY_KEY, setAuthSession } from "@/lib/authSession";

const defaultBranding: BusinessBrandingSettings = {
  logo_url: null,
  owner_profile_image_url: null,
  display_image_url: null,
  theme: {
    primary_color: "#1E3A5F",
    secondary_color: "#284B73",
    sidebar_color: "#1E3A5F",
    accent_color: "#3B82F6",
    button_color: "#1E3A5F",
    card_style: "soft",
    font_size: "comfortable",
    color_mode: "light",
    layout_density: "rounded",
  },
};

export function OwnerAccountSettingsPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    business_name: "",
    owner_name: "",
    email: "",
    contact_phone: "",
    address: "",
    business_type: "",
  });
  const [branding, setBranding] =
    useState<BusinessBrandingSettings>(defaultBranding);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["account-settings"],
    queryFn: getAccountSettings,
  });

  useEffect(() => {
    if (!data) return;
    setForm({
      business_name: data.business_name,
      owner_name: data.owner_name ?? "",
      email: data.email,
      contact_phone: data.contact_phone ?? "",
      address: data.address,
      business_type: data.business_type ?? "",
    });
    setBranding(data.branding ?? defaultBranding);
  }, [data]);

  const save = useMutation({
    mutationFn: () =>
      updateAccountSettings({
        business_name: form.business_name.trim(),
        owner_name: form.owner_name.trim(),
        contact_phone: form.contact_phone.trim() || null,
        address: form.address.trim(),
        business_type: form.business_type.trim() || null,
        branding,
      }),
    onSuccess: () => {
      toast.success("Account settings saved");
      qc.invalidateQueries({ queryKey: ["account-settings"] });
      qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
    },
    onError: () => toast.error("Failed to save account settings"),
  });

  const changePasswordMutation = useMutation({
    mutationFn: () => changePassword(currentPassword, newPassword),
    onSuccess: (res) => {
      setAuthSession(res.access_token);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      toast.success("Password updated");
    },
    onError: () => toast.error("Failed to update password"),
  });

  const canSave =
    form.business_name.trim().length >= 2 &&
    form.owner_name.trim().length >= 2 &&
    form.address.trim().length >= 5;

  const canChangePassword =
    currentPassword.length > 0 &&
    newPassword.length >= 8 &&
    newPassword === confirmPassword;

  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-3xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">Account Settings</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Manage your personal, business, and contact information.
          </p>
        </div>

        {isLoading && (
          <p className="text-sm text-muted-foreground">Loading account settings...</p>
        )}
        {isError && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Unable to load account settings.
          </p>
        )}

        {!isLoading && !isError && (
          <>
            <Card>
              <CardHeader>
                <CardTitle>Personal</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="owner-name">Owner Name</Label>
                  <Input
                    id="owner-name"
                    value={form.owner_name}
                    onChange={(e) =>
                      setForm({ ...form, owner_name: e.target.value })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="owner-email">Email</Label>
                  <Input id="owner-email" value={form.email} disabled />
                  <p className="text-xs text-muted-foreground">
                    Email cannot be changed here. Contact support if needed.
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Business</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="business-name">Business Name</Label>
                  <Input
                    id="business-name"
                    value={form.business_name}
                    onChange={(e) =>
                      setForm({ ...form, business_name: e.target.value })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="business-type">Business Type</Label>
                  <Input
                    id="business-type"
                    value={form.business_type}
                    onChange={(e) =>
                      setForm({ ...form, business_type: e.target.value })
                    }
                    placeholder="e.g. Cafe, Restaurant, Retail"
                  />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Contact</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="contact-phone">Contact Number</Label>
                  <Input
                    id="contact-phone"
                    value={form.contact_phone}
                    onChange={(e) =>
                      setForm({ ...form, contact_phone: e.target.value })
                    }
                    placeholder="+63 912 345 6789"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="business-address">Business Address</Label>
                  <Input
                    id="business-address"
                    value={form.address}
                    onChange={(e) =>
                      setForm({ ...form, address: e.target.value })
                    }
                  />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Security</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="current-password">Current Password</Label>
                  <Input
                    id="current-password"
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="new-password">New Password</Label>
                  <Input
                    id="new-password"
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="confirm-password">Confirm New Password</Label>
                  <Input
                    id="confirm-password"
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                  />
                </div>
                <Button
                  variant="outline"
                  onClick={() => changePasswordMutation.mutate()}
                  disabled={!canChangePassword || changePasswordMutation.isPending}
                >
                  Update Password
                </Button>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Business Branding & Theme</CardTitle>
                <p className="text-sm text-muted-foreground">
                  Customize your business logo, profile image, and theme for
                  this business account and connected employee experience.
                </p>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="grid gap-4 md:grid-cols-3">
                  <ImageUploadField
                    label="Business Logo"
                    value={branding.logo_url}
                    onChange={(value) =>
                      setBranding({ ...branding, logo_url: value })
                    }
                  />
                  <ImageUploadField
                    label="Owner Profile Picture"
                    value={branding.owner_profile_image_url}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        owner_profile_image_url: value,
                      })
                    }
                  />
                  <ImageUploadField
                    label="Business Display Image"
                    value={branding.display_image_url}
                    onChange={(value) =>
                      setBranding({ ...branding, display_image_url: value })
                    }
                  />
                </div>

                <div className="grid gap-4 md:grid-cols-2">
                  <ColorField
                    label="Primary Color"
                    value={branding.theme.primary_color}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, primary_color: value },
                      })
                    }
                  />
                  <ColorField
                    label="Secondary Color"
                    value={branding.theme.secondary_color}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, secondary_color: value },
                      })
                    }
                  />
                  <ColorField
                    label="Sidebar Color"
                    value={branding.theme.sidebar_color}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, sidebar_color: value },
                      })
                    }
                  />
                  <ColorField
                    label="Accent Color"
                    value={branding.theme.accent_color}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, accent_color: value },
                      })
                    }
                  />
                  <ColorField
                    label="Button Color"
                    value={branding.theme.button_color}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, button_color: value },
                      })
                    }
                  />
                  <SelectField
                    label="Card Style"
                    value={branding.theme.card_style}
                    options={["soft", "flat", "outlined"]}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, card_style: value },
                      })
                    }
                  />
                  <SelectField
                    label="Font Size Preference"
                    value={branding.theme.font_size}
                    options={["compact", "comfortable", "large"]}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, font_size: value },
                      })
                    }
                  />
                  <SelectField
                    label="Mode"
                    value={branding.theme.color_mode}
                    options={["light", "dark"]}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, color_mode: value },
                      })
                    }
                  />
                  <SelectField
                    label="Layout Style"
                    value={branding.theme.layout_density}
                    options={["rounded", "compact"]}
                    onChange={(value) =>
                      setBranding({
                        ...branding,
                        theme: { ...branding.theme, layout_density: value },
                      })
                    }
                  />
                </div>
              </CardContent>
            </Card>

            <Button
              onClick={() => save.mutate()}
              disabled={!canSave || save.isPending}
            >
              Save Changes
            </Button>
          </>
        )}
      </div>
    </div>
  );
}

function ImageUploadField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string | null;
  onChange: (value: string | null) => void;
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
      <div className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
        <div className="flex h-24 items-center justify-center overflow-hidden rounded-xl bg-white">
          {value ? (
            <img className="h-full w-full object-cover" src={value} alt={label} />
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
          {value && (
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => onChange(null)}
            >
              Remove
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

function ColorField({
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

function SelectField({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: string[];
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <select
        className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </div>
  );
}
