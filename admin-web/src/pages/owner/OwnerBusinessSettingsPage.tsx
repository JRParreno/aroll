import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Building2, FileText, Palette } from "lucide-react";
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
import {
  DetailField,
  DetailSection,
  StatusBadge,
} from "@/components/detail/DetailLayout";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  fetchOwnerRegistrationDocumentFile,
  getBusinessLegalSettings,
  getBusinessSettings,
  listConsentDocuments,
  updateBusinessLegalSettings,
  updateBusinessSettings,
  type BusinessBrandingSettings,
} from "@/lib/api";
import { ConsentDocumentManager } from "@/components/consents/ConsentDocumentManager";
import { ME_QUERY_KEY } from "@/lib/authSession";
import { formatBusinessType, formatVerificationStatus } from "@/lib/registrationDocuments";

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
  const [useCustomConsents, setUseCustomConsents] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["business-settings"],
    queryFn: getBusinessSettings,
  });

  const { data: legalData } = useQuery({
    queryKey: ["business-legal"],
    queryFn: getBusinessLegalSettings,
  });
  const { data: consentCatalog, isLoading: consentsLoading } = useQuery({
    queryKey: ["owner-consents"],
    queryFn: () => listConsentDocuments("owner"),
  });

  useEffect(() => {
    if (!legalData) return;
    setUseCustomConsents(legalData.use_custom_consents);
  }, [legalData]);

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

  const saveLegal = useMutation({
    mutationFn: () =>
      updateBusinessLegalSettings({
        use_custom_consents: useCustomConsents,
      }),
    onSuccess: () => {
      toast.success("Consent settings saved");
      qc.invalidateQueries({ queryKey: ["business-legal"] });
      qc.invalidateQueries({ queryKey: ["owner-consents"] });
    },
    onError: () => toast.error("Failed to save consent settings"),
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
      <OwnerPageContent className="max-w-4xl">
        <OwnerPageBackLink to="/owner/settings/setup" label="Back to Business Setup" />

        <Card>
          <CardHeader>
            <CardTitle className="text-[1.0625rem] font-semibold leading-snug tracking-[-0.015em]">
              Business Information
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2 md:col-span-2">
              <Label htmlFor="business-name">Business Name</Label>
              <Input
                id="business-name"
                value={form.business_name}
                onChange={(event) =>
                  setForm({ ...form, business_name: event.target.value })
                }
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="business-type">Business Type</Label>
              <Input
                id="business-type"
                value={form.business_type}
                onChange={(event) =>
                  setForm({ ...form, business_type: event.target.value })
                }
                placeholder="e.g. Cafe, Restaurant, Retail"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="business-code">Business Code</Label>
              <Input id="business-code" value={form.business_code} disabled />
            </div>
            <div className="space-y-2 md:col-span-2">
              <Label htmlFor="business-address">Business Address</Label>
              <Input
                id="business-address"
                value={form.address}
                onChange={(event) =>
                  setForm({ ...form, address: event.target.value })
                }
              />
            </div>
            {verificationStatus ? (
              <div className="md:col-span-2">
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Registration Status
                </p>
                <div className="mt-1">
                  <StatusBadge status={verificationStatus} />
                </div>
              </div>
            ) : null}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-[1.0625rem] font-semibold leading-snug tracking-[-0.015em]">
              <Palette className="h-4 w-4" />
              Business Branding & Theme
            </CardTitle>
            <p className="owner-section-subtitle mt-1">
              Logo and brand colors appear in the owner portal and employee
              mobile app. The separate display image field was removed in favor
              of the business logo.
            </p>
          </CardHeader>
          <CardContent>
            <BusinessLogoAndThemeFields
              branding={branding}
              onChange={setBranding}
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-[1.0625rem] font-semibold leading-snug tracking-[-0.015em]">
              Workplace consents
            </CardTitle>
            <p className="owner-section-subtitle mt-1">
              Employees always load consents from the API. This workplace uses
              Aroll+ Admin defaults unless you enable custom workplace consents.
            </p>
          </CardHeader>
          <CardContent className="space-y-4">
            <label className="flex items-start gap-3 rounded-lg border border-slate-200 px-3 py-3 text-sm">
              <input
                type="checkbox"
                className="mt-1"
                checked={useCustomConsents}
                onChange={(event) => setUseCustomConsents(event.target.checked)}
              />
              <span>
                <span className="font-medium">Use custom workplace consents</span>
                <span className="mt-1 block text-muted-foreground">
                  Off by default. When on, employees see only this workplace’s
                  documents. Incomplete or unpublished custom catalogs fail
                  closed and do not fall back to Admin defaults.
                </span>
              </span>
            </label>
            <Button
              type="button"
              onClick={() => saveLegal.mutate()}
              disabled={saveLegal.isPending}
            >
              {saveLegal.isPending ? "Saving…" : "Save consent toggle"}
            </Button>
            {consentsLoading ? (
              <p className="text-sm text-muted-foreground">Loading consents…</p>
            ) : useCustomConsents ? (
              <ConsentDocumentManager
                scope="owner"
                documents={consentCatalog?.documents ?? []}
                canEdit={consentCatalog?.can_edit === true}
                onChanged={() => {
                  qc.invalidateQueries({ queryKey: ["owner-consents"] });
                }}
              />
            ) : (
              <ConsentDocumentManager
                scope="owner"
                documents={consentCatalog?.documents ?? []}
                canEdit={false}
                readOnlyHint="Admin defaults apply. Turn on custom workplace consents to upload or edit documents for this workplace only."
                onChanged={() => {
                  qc.invalidateQueries({ queryKey: ["owner-consents"] });
                }}
              />
            )}
          </CardContent>
        </Card>

        <DetailSection
          title="Owner Information"
          description="Read-only owner contact details from registration."
          icon={<Building2 className="h-4 w-4" />}
        >
          <DetailField label="Owner Name" value={data.owner_name ?? "—"} />
          <DetailField label="Email" value={data.owner_email} />
          <DetailField label="Phone" value={data.owner_phone ?? "Not provided"} />
        </DetailSection>

        <DetailSection
          title="Uploaded Registration Documents"
          description="Official compliance documents submitted during registration."
          icon={<FileText className="h-4 w-4" />}
        >
          <BusinessRegistrationDocumentsSection
            registrationId={data.registration_id}
            documents={data.registration_documents}
            fetchDocumentFile={fetchOwnerDocument}
          />
        </DetailSection>

        <Button onClick={() => save.mutate()} disabled={!canSave || save.isPending}>
          Save Business Settings
        </Button>
      </OwnerPageContent>
    </OwnerPage>
  );
}
