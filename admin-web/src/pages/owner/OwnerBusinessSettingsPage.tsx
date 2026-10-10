import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronDown } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { BusinessRegistrationDocumentsSection } from "@/components/business/BusinessRegistrationDocumentsSection";
import {
  BusinessLogoAndThemeFields,
} from "@/components/owner/settings/brandingFormFields";
import {
  businessBrandingForSave,
  defaultBusinessBranding,
} from "@/components/owner/settings/brandingDefaults";
import { StatusBadge } from "@/components/detail/DetailLayout";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  fetchOwnerRegistrationDocumentFile,
  getBusinessSettings,
  updateBusinessSettings,
  type BusinessBrandingSettings,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";
import { formatVerificationStatus } from "@/lib/registrationDocuments";

async function fetchOwnerDocument(
  _registrationId: string,
  documentId: string
) {
  return fetchOwnerRegistrationDocumentFile(documentId);
}

export function OwnerBusinessSettingsPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    business_name: "",
    business_type: "",
    address: "",
    business_code: "",
  });
  const [branding, setBranding] =
    useState<BusinessBrandingSettings>(defaultBusinessBranding);
  const [documentsOpen, setDocumentsOpen] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["business-settings"],
    queryFn: getBusinessSettings,
  });

  useEffect(() => {
    if (!data) return;
    setForm({
      business_name: data.business_name,
      business_type: data.business_type ?? "",
      address: data.address,
      business_code: data.business_code,
    });
    setBranding(data.branding ?? defaultBusinessBranding);
  }, [data]);

  const save = useMutation({
    mutationFn: () =>
      updateBusinessSettings({
        business_name: form.business_name.trim(),
        business_type: form.business_type.trim() || null,
        address: form.address.trim(),
        branding: businessBrandingForSave(branding),
      }),
    onSuccess: () => {
      toast.success("Business settings saved");
      qc.invalidateQueries({ queryKey: ["business-settings"] });
      qc.invalidateQueries({ queryKey: ME_QUERY_KEY });
    },
    onError: () => toast.error("Failed to save business settings"),
  });

  if (isLoading) {
    return (
      <OwnerPage>
        <OwnerPageHeader
          title="Business Settings"
          description="Business profile, branding, and registration documents."
        />
        <OwnerPageContent className="max-w-4xl">
          <p className="text-sm text-muted-foreground">Loading business settings…</p>
        </OwnerPageContent>
      </OwnerPage>
    );
  }

  if (isError || !data) {
    return (
      <OwnerPage>
        <OwnerPageHeader
          title="Business Settings"
          description="Business profile, branding, and registration documents."
        />
        <OwnerPageContent className="max-w-4xl">
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Unable to load business settings. Please try again.
          </p>
        </OwnerPageContent>
      </OwnerPage>
    );
  }

  const verificationStatus = data.application_status
    ? formatVerificationStatus(data.application_status)
    : null;

  const canSave =
    form.business_name.trim().length >= 2 && form.address.trim().length >= 5;

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Business Settings"
        description="Business profile, branding, and registration documents."
      />
      <OwnerPageContent className="max-w-4xl space-y-4">
        <OwnerPageBackLink to="/owner/settings/setup" label="Back to Business Setup" />

        <OwnerCard className="overflow-hidden">
          <div className="flex flex-col items-start gap-3 border-b border-slate-200/80 bg-[#F7F8FA] px-4 py-4 sm:flex-row sm:items-center sm:gap-4 sm:px-5">
            {branding.logo_url ? (
              <img
                src={branding.logo_url}
                alt=""
                className="h-14 w-14 shrink-0 rounded-full object-cover ring-1 ring-slate-200"
              />
            ) : (
              <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-[var(--owner-well)] text-base font-semibold text-[var(--owner-navy)] ring-1 ring-slate-200">
                {(form.business_name || "B").slice(0, 1).toUpperCase()}
              </div>
            )}
            <div className="min-w-0">
              <h2 className="truncate text-lg font-semibold tracking-tight text-[#111827]">
                {form.business_name.trim() || "Business"}
              </h2>
              <p className="truncate text-sm text-[#6B7280]">
                {form.business_type.trim() || "Business type not set"}
              </p>
              <p className="mt-0.5 truncate text-xs text-[#6B7280]">
                Business code: {form.business_code || "—"}
              </p>
              {verificationStatus ? (
                <div className="mt-2">
                  <StatusBadge status={verificationStatus} />
                </div>
              ) : null}
            </div>
          </div>
          <div className="px-4 py-4 sm:px-5">
            <h3 className="text-sm font-semibold text-[#111827]">Business details</h3>
            <p className="mt-1 text-sm text-[#6B7280]">
              Update the profile shown for this business.
            </p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <div className="space-y-1.5 sm:col-span-2">
                <Label htmlFor="business-name">Business name</Label>
                <Input
                  id="business-name"
                  value={form.business_name}
                  onChange={(event) =>
                    setForm({ ...form, business_name: event.target.value })
                  }
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="business-type">Business type</Label>
                <Input
                  id="business-type"
                  value={form.business_type}
                  onChange={(event) =>
                    setForm({ ...form, business_type: event.target.value })
                  }
                  placeholder="e.g. Cafe, Restaurant, Retail"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="business-code">Business code</Label>
                <Input id="business-code" value={form.business_code} disabled />
              </div>
              <div className="space-y-1.5 sm:col-span-2">
                <Label htmlFor="business-address">Address</Label>
                <Input
                  id="business-address"
                  value={form.address}
                  onChange={(event) =>
                    setForm({ ...form, address: event.target.value })
                  }
                />
              </div>
            </div>
          </div>
        </OwnerCard>

        <OwnerCard className="px-4 py-4 sm:px-5">
          <h2 className="text-[1.0625rem] font-semibold tracking-tight text-[#111827]">
            Branding and appearance
          </h2>
          <p className="mt-1 text-sm text-[#6B7280]">
            Logo and brand style appear in the owner portal and employee app.
          </p>
          <div className="mt-4">
            <BusinessLogoAndThemeFields
              branding={branding}
              savedTheme={(data.branding ?? defaultBusinessBranding).theme}
              businessName={form.business_name}
              onChange={setBranding}
            />
          </div>
        </OwnerCard>

        <OwnerCard className="overflow-hidden">
          <button
            type="button"
            className="flex w-full flex-wrap items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--owner-navy)] sm:px-5"
            aria-expanded={documentsOpen}
            onClick={() => setDocumentsOpen((open) => !open)}
          >
            <span className="min-w-0 flex-1">
              <span className="block text-[1.0625rem] font-semibold tracking-tight text-[#111827]">
                Registration documents
              </span>
              <span className="mt-0.5 block text-sm text-[#6B7280]">
                Supporting business registration documents
              </span>
            </span>
            <span className="shrink-0 text-xs font-medium text-[#6B7280]">
              {data.registration_documents.length}{" "}
              {data.registration_documents.length === 1 ? "document" : "documents"}
            </span>
            <ChevronDown
              className={`h-4 w-4 shrink-0 text-[#6B7280] transition-transform duration-150 ${
                documentsOpen ? "rotate-180" : ""
              }`}
              aria-hidden="true"
            />
          </button>
          {documentsOpen ? (
            <div className="border-t border-slate-200 px-4 py-4 sm:px-5">
              <BusinessRegistrationDocumentsSection
                registrationId={data.registration_id}
                documents={data.registration_documents}
                fetchDocumentFile={fetchOwnerDocument}
              />
            </div>
          ) : null}
        </OwnerCard>

        <Button onClick={() => save.mutate()} disabled={!canSave || save.isPending}>
          Save Business Settings
        </Button>
      </OwnerPageContent>
    </OwnerPage>
  );
}
