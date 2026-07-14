import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import {
  ImageUploadField,
} from "@/components/owner/settings/brandingFormFields";
import { defaultBusinessBranding } from "@/components/owner/settings/brandingDefaults";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
} from "@/components/owner/layout/OwnerPageLayout";
import {
  PasswordInput,
  PasswordRequirements,
} from "@/components/ui/password-input";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { changePassword, getAccountSettings, removeOwnerProfileImage, updateAccountSettings, updateOwnerProfileImage } from "@/lib/api";
import { canSubmitPasswordChange } from "@/lib/passwordValidation";
import { ME_QUERY_KEY, setAuthSession } from "@/lib/authSession";

export function OwnerAccountSettingsPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    owner_name: "",
    email: "",
    contact_phone: "",
    business_name: "",
    address: "",
    business_type: "",
  });
  const [ownerProfileImage, setOwnerProfileImage] = useState<string | null>(null);
  const [photoHydrated, setPhotoHydrated] = useState(false);
  const [photoUpdating, setPhotoUpdating] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["account-settings"],
    queryFn: getAccountSettings,
    refetchOnWindowFocus: true,
  });

  useEffect(() => {
    if (!data) return;
    setForm({
      owner_name: data.owner_name ?? "",
      email: data.email,
      contact_phone: data.contact_phone ?? "",
      business_name: data.business_name,
      address: data.address,
      business_type: data.business_type ?? "",
    });
  }, [data]);

  useEffect(() => {
    if (!data || photoHydrated || photoUpdating) return;
    setOwnerProfileImage(
      data.branding?.owner_profile_image_url ?? defaultBusinessBranding.owner_profile_image_url
    );
    setPhotoHydrated(true);
  }, [data, photoHydrated, photoUpdating]);

  const save = useMutation({
    mutationFn: () =>
      updateAccountSettings({
        business_name: data?.business_name ?? form.business_name,
        owner_name: form.owner_name.trim(),
        contact_phone: form.contact_phone.trim() || null,
        address: data?.address ?? form.address,
        business_type: data?.business_type ?? (form.business_type.trim() || null),
        branding: {
          ...(data?.branding ?? defaultBusinessBranding),
          owner_profile_image_url: ownerProfileImage,
        },
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

  const canSave = form.owner_name.trim().length >= 2;
  const canChangePassword = canSubmitPasswordChange({
    currentPassword,
    newPassword,
    confirmPassword,
  });

  async function handleOwnerProfileImageChange(value: string | null) {
    const previous = ownerProfileImage;
    setOwnerProfileImage(value);
    setPhotoUpdating(true);
    try {
      let imageUrl: string | null = null;
      if (value) {
        const result = await updateOwnerProfileImage(value);
        imageUrl = result.owner_profile_image_url;
        setOwnerProfileImage(imageUrl);
      } else {
        await removeOwnerProfileImage();
        setOwnerProfileImage(null);
      }
      toast.success(value ? "Profile picture updated" : "Profile picture removed");
      qc.setQueryData(ME_QUERY_KEY, (current) => {
        if (!current?.branding) return current;
        return {
          ...current,
          branding: {
            ...current.branding,
            owner_profile_image_url: imageUrl,
          },
        };
      });
      qc.invalidateQueries({ queryKey: ["account-settings"] });
      qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
    } catch {
      setOwnerProfileImage(previous);
      toast.error("Failed to update profile picture");
    } finally {
      setPhotoUpdating(false);
    }
  }

  return (
    <OwnerPage>
      <OwnerPageContent className="max-w-3xl">
        <OwnerPageBackLink to="/owner/settings/setup" label="Back to Business Setup" />

        <div>
          <h1 className="text-2xl font-semibold">Account Settings</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Manage your profile picture, personal information, and password.
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
                <CardTitle>Profile Picture</CardTitle>
              </CardHeader>
              <CardContent>
                <ImageUploadField
                  label="Owner Profile Picture"
                  value={ownerProfileImage}
                  onChange={handleOwnerProfileImageChange}
                />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Personal Information</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="owner-name">Owner Name</Label>
                  <Input
                    id="owner-name"
                    value={form.owner_name}
                    onChange={(event) =>
                      setForm({ ...form, owner_name: event.target.value })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="contact-phone">Contact Number</Label>
                  <Input
                    id="contact-phone"
                    value={form.contact_phone}
                    onChange={(event) =>
                      setForm({ ...form, contact_phone: event.target.value })
                    }
                    placeholder="+63 912 345 6789"
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
                <CardTitle>Security</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <PasswordInput
                  id="current-password"
                  label="Current Password"
                  value={currentPassword}
                  onChange={setCurrentPassword}
                />
                <PasswordInput
                  id="new-password"
                  label="New Password"
                  value={newPassword}
                  onChange={setNewPassword}
                />
                <PasswordInput
                  id="confirm-password"
                  label="Confirm New Password"
                  value={confirmPassword}
                  onChange={setConfirmPassword}
                />
                <PasswordRequirements
                  password={newPassword}
                  confirmPassword={confirmPassword}
                />
                <Button
                  variant="outline"
                  onClick={() => changePasswordMutation.mutate()}
                  disabled={!canChangePassword || changePasswordMutation.isPending}
                >
                  Update Password
                </Button>
              </CardContent>
            </Card>

            <Button onClick={() => save.mutate()} disabled={!canSave || save.isPending}>
              Save Changes
            </Button>
          </>
        )}
      </OwnerPageContent>
    </OwnerPage>
  );
}
