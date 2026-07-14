import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { defaultBusinessBranding } from "@/components/owner/settings/brandingDefaults";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  getAccountSettings,
  removeOwnerProfileImage,
  updateAccountSettings,
  updateOwnerProfileImage,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

const OWNER_DOB_KEY = "aroll_owner_date_of_birth";

function profileImageErrorMessage(error: unknown, action: "update" | "remove") {
  if (error && typeof error === "object" && "response" in error) {
    const response = (error as { response?: { status?: number; data?: { detail?: string } } })
      .response;
    const detail = response?.data?.detail;
    if (response?.status === 400 && typeof detail === "string") {
      return detail;
    }
    if (response?.status === 401 || response?.status === 403) {
      return `You are not authorized to ${action} your profile picture.`;
    }
  }
  return `Failed to ${action} profile picture.`;
}

export function OwnerProfilePage() {
  const qc = useQueryClient();
  const [photo, setPhoto] = useState<string | null>(null);
  const [photoHydrated, setPhotoHydrated] = useState(false);
  const [dateOfBirth, setDateOfBirth] = useState(() => localStorage.getItem(OWNER_DOB_KEY) ?? "");
  const [form, setForm] = useState({
    business_name: "",
    owner_name: "",
    email: "",
    contact_phone: "",
    address: "",
    business_type: "",
  });

  const { data, isLoading } = useQuery({
    queryKey: ["account-settings"],
    queryFn: getAccountSettings,
    refetchOnWindowFocus: true,
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
  }, [data]);

  const invalidateProfileQueries = () => {
    qc.invalidateQueries({ queryKey: ["account-settings"] });
    qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
  };

  const syncOwnerPhotoInCache = (imageUrl: string | null) => {
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
    qc.setQueryData(["account-settings"], (current) => {
      if (!current?.branding) return current;
      return {
        ...current,
        branding: {
          ...current.branding,
          owner_profile_image_url: imageUrl,
        },
      };
    });
  };

  const uploadPhoto = useMutation({
    mutationFn: (imageData: string) => updateOwnerProfileImage(imageData),
    onSuccess: (result) => {
      setPhoto(result.owner_profile_image_url);
      syncOwnerPhotoInCache(result.owner_profile_image_url);
      invalidateProfileQueries();
      toast.success("Profile picture updated");
    },
    onError: (error) => toast.error(profileImageErrorMessage(error, "update")),
  });

  const removePhoto = useMutation({
    mutationFn: removeOwnerProfileImage,
    onSuccess: () => {
      setPhoto(null);
      syncOwnerPhotoInCache(null);
      invalidateProfileQueries();
      toast.success("Profile picture removed");
    },
    onError: (error) => toast.error(profileImageErrorMessage(error, "remove")),
  });

  useEffect(() => {
    if (!data || photoHydrated || uploadPhoto.isPending || removePhoto.isPending) {
      return;
    }
    setPhoto(
      data.branding?.owner_profile_image_url ??
        defaultBusinessBranding.owner_profile_image_url
    );
    setPhotoHydrated(true);
  }, [data, photoHydrated, uploadPhoto.isPending, removePhoto.isPending]);

  const save = useMutation({
    mutationFn: () =>
      updateAccountSettings({
        business_name: form.business_name.trim(),
        owner_name: form.owner_name.trim(),
        contact_phone: form.contact_phone.trim() || null,
        address: form.address.trim(),
        business_type: form.business_type.trim() || null,
        branding: {
          ...(data?.branding ?? defaultBusinessBranding),
          owner_profile_image_url: photo,
        },
      }),
    onSuccess: () => {
      localStorage.setItem(OWNER_DOB_KEY, dateOfBirth);
      toast.success("Profile updated");
      invalidateProfileQueries();
    },
    onError: () => toast.error("Failed to update profile"),
  });

  function handlePhoto(file: File | null) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const value = String(reader.result);
      setPhoto(value);
      uploadPhoto.mutate(value);
    };
    reader.readAsDataURL(file);
  }

  const photoBusy = uploadPhoto.isPending || removePhoto.isPending;

  return (
    <OwnerPage>
      <OwnerPageContent className="max-w-4xl">
        <OwnerPageBackLink to="/owner/settings/account" label="Back to Account Settings" />

        <div>
          <h1 className="text-2xl font-semibold text-[#1F2937]">Owner Profile</h1>
        </div>

        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="flex flex-col gap-5 sm:flex-row sm:items-center">
            <div className="relative h-24 w-24 overflow-hidden rounded-full bg-slate-100">
              {photo ? (
                <img className="h-full w-full object-cover" src={photo} alt="Owner profile" />
              ) : (
                <div className="flex h-full w-full items-center justify-center text-2xl font-semibold text-[#6B7280]">
                  {form.owner_name.slice(0, 1).toUpperCase() || "O"}
                </div>
              )}
            </div>
            <div>
              <h2 className="text-xl font-semibold text-[#1F2937]">
                {form.owner_name || "Business Owner"}
              </h2>
              <p className="text-sm text-[#6B7280]">{form.business_name}</p>
              <div className="mt-3 flex flex-wrap gap-2">
                <label className="inline-flex cursor-pointer items-center gap-2 rounded-xl border border-slate-200 px-3 py-2 text-sm font-medium text-[#374151]">
                  <Camera className="h-4 w-4" />
                  {photoBusy ? "Saving..." : "Change photo"}
                  <input
                    className="hidden"
                    type="file"
                    accept="image/*"
                    disabled={photoBusy}
                    onChange={(e) => handlePhoto(e.target.files?.[0] ?? null)}
                  />
                </label>
                {photo ? (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    disabled={photoBusy}
                    onClick={() => removePhoto.mutate()}
                  >
                    Remove profile picture
                  </Button>
                ) : null}
              </div>
            </div>
          </div>
        </section>

        <section className="grid gap-6 xl:grid-cols-2">
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="mb-4 text-lg font-semibold text-[#1F2937]">Personal Information</h2>
            <div className="space-y-4">
              <Field label="Full Name" value={form.owner_name} onChange={(value) => setForm({ ...form, owner_name: value })} />
              <Field label="Contact Number" value={form.contact_phone} onChange={(value) => setForm({ ...form, contact_phone: value })} />
              <Field label="Address" value={form.address} onChange={(value) => setForm({ ...form, address: value })} />
              <Field label="Date of Birth" type="date" value={dateOfBirth} onChange={setDateOfBirth} />
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="mb-4 text-lg font-semibold text-[#1F2937]">Business Information</h2>
            <div className="space-y-4">
              <Field label="Business Name" value={form.business_name} onChange={(value) => setForm({ ...form, business_name: value })} />
              <Field label="Business Type" value={form.business_type} onChange={(value) => setForm({ ...form, business_type: value })} />
              <Field label="Business Address" value={form.address} onChange={(value) => setForm({ ...form, address: value })} />
              <Field label="Email" value={form.email} disabled onChange={() => undefined} />
            </div>
          </div>
        </section>

        <div className="flex justify-end">
          <Button className="bg-[#1E3A5F] hover:bg-[#284B73]" disabled={isLoading || save.isPending} onClick={() => save.mutate()}>
            Save Profile
          </Button>
        </div>
      </OwnerPageContent>
    </OwnerPage>
  );
}

function Field({
  label,
  value,
  onChange,
  type = "text",
  disabled = false,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  disabled?: boolean;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Input disabled={disabled} type={type} value={value} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}
