import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Building2, FileText, Palette } from "lucide-react";
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
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
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  fetchOwnerRegistrationDocumentFile,
  getBusinessLegalSettings,
  getBusinessSettings,
  updateBusinessLegalSettings,
  updateBusinessSettings,
  type BusinessBrandingSettings,
} from "@/lib/api";
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
  const [legalCustom, setLegalCustom] = useState({
    terms_content: "",
    privacy_content: "",
    biometric_consent_content: "",
    terms_version: "",
    privacy_version: "",
    biometric_consent_version: "",
  });
  const [useCustomConsents, setUseCustomConsents] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["business-settings"],
    queryFn: getBusinessSettings,
  });

  const { data: legalData } = useQuery({
    queryKey: ["business-legal"],
    queryFn: getBusinessLegalSettings,
  });

  useEffect(() => {
    if (!legalData) return;
    setUseCustomConsents(legalData.use_custom_consents);
    setLegalCustom({
      terms_content: legalData.custom.terms_content ?? "",
      privacy_content: legalData.custom.privacy_content ?? "",
      biometric_consent_content:
        legalData.custom.biometric_consent_content ?? "",
      terms_version: legalData.custom.terms_version ?? "",
      privacy_version: legalData.custom.privacy_version ?? "",
      biometric_consent_version:
        legalData.custom.biometric_consent_version ?? "",
    });
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
        terms_content: legalCustom.terms_content,
        privacy_content: legalCustom.privacy_content,
        biometric_consent_content: legalCustom.biometric_consent_content,
        terms_version: legalCustom.terms_version,
        privacy_version: legalCustom.privacy_version,
        biometric_consent_version: legalCustom.biometric_consent_version,
      }),
    onSuccess: () => {
      toast.success("Legal page saved");
      qc.invalidateQueries({ queryKey: ["business-legal"] });
    },
    onError: () => toast.error("Failed to save legal page"),
  });

  if (isLoading) {
    return (
      <OwnerPage>
        <OwnerPageContent className="max-w-4xl">
          <p className="text-sm text-muted-foreground">Loading business settings…</p>
        </OwnerPageContent>
      </OwnerPage>
    );
  }

  if (isError || !data) {
    return (
      <OwnerPage>
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
      <OwnerPageContent className="max-w-4xl">
        <OwnerPageBackLink to="/owner/settings/setup" label="Back to Business Setup" />

        <div>
          <h1 className="text-2xl font-semibold">Business Settings</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Business profile, branding, and registration documents.
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Business Information</CardTitle>
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
            <CardTitle className="flex items-center gap-2">
              <Palette className="h-4 w-4" />
              Business Branding & Theme
            </CardTitle>
            <p className="text-sm text-muted-foreground">
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
            <CardTitle>Legal Content</CardTitle>
            <p className="text-sm text-muted-foreground">
              This workplace uses Aroll+ default Terms, Privacy, and Biometric
              Consent unless you enable a custom override. Employees review the
              effective page at the generated URL. You are not required to write
              legal copy.
            </p>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Effective legal page
              </p>
              <div className="mt-1 flex flex-wrap items-center gap-3">
                <code className="text-xs">
                  {legalData?.legal_page_url ||
                    `/legal/b/${form.business_code}`}
                </code>
                {form.business_code ? (
                  <Link
                    className="text-sm font-medium text-[#1E3A5F] underline"
                    to={`/legal/b/${form.business_code}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Preview
                  </Link>
                ) : null}
              </div>
              <p className="mt-2 text-sm font-medium text-slate-800">
                {useCustomConsents
                  ? "Custom for this workplace"
                  : "Using Aroll+ Defaults"}
              </p>
            </div>

            <label className="flex items-start gap-3 rounded-lg border border-slate-200 px-3 py-3 text-sm">
              <input
                type="checkbox"
                className="mt-1"
                checked={useCustomConsents}
                onChange={(event) => setUseCustomConsents(event.target.checked)}
              />
              <span>
                <span className="font-medium">Use custom legal content</span>
                <span className="mt-1 block text-muted-foreground">
                  When off, employees see the current Aroll+ defaults. When on,
                  this workplace must publish its own Terms, Privacy, and
                  Biometric Consent. Incomplete custom content cannot be
                  accepted.
                </span>
              </span>
            </label>

            <div className="space-y-3 rounded-lg border border-slate-200 p-3">
              <p className="text-sm font-medium text-slate-800">
                Aroll+ defaults (read-only)
              </p>
              {(
                [
                  ["terms", "Terms and Conditions"],
                  ["privacy", "Privacy Policy"],
                  ["biometric", "Biometric Consent"],
                ] as const
              ).map(([key, label]) => {
                const section = legalData?.defaults?.[key];
                return (
                  <div key={key} className="space-y-1">
                    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      {label}
                      {section?.version ? ` · ${section.version}` : ""}
                      {section?.published === false ? " · unpublished" : ""}
                    </p>
                    <pre className="max-h-40 overflow-auto whitespace-pre-wrap rounded-md bg-slate-50 p-3 text-xs leading-5 text-slate-700">
                      {section?.content || "No platform default published yet."}
                    </pre>
                  </div>
                );
              })}
            </div>

            {useCustomConsents ? (
              <>
                {(
                  [
                    ["terms_content", "terms_version", "Terms and Conditions"],
                    ["privacy_content", "privacy_version", "Privacy Policy"],
                    [
                      "biometric_consent_content",
                      "biometric_consent_version",
                      "Biometric Consent",
                    ],
                  ] as const
                ).map(([contentKey, versionKey, label]) => (
                  <div key={contentKey} className="space-y-2">
                    <div className="flex items-end gap-3">
                      <div className="flex-1 space-y-2">
                        <Label htmlFor={contentKey}>{label}</Label>
                        <textarea
                          id={contentKey}
                          className="min-h-32 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                          value={legalCustom[contentKey]}
                          onChange={(event) =>
                            setLegalCustom({
                              ...legalCustom,
                              [contentKey]: event.target.value,
                            })
                          }
                        />
                      </div>
                      <div className="w-48 space-y-2">
                        <Label htmlFor={versionKey}>Version</Label>
                        <Input
                          id={versionKey}
                          value={legalCustom[versionKey]}
                          onChange={(event) =>
                            setLegalCustom({
                              ...legalCustom,
                              [versionKey]: event.target.value,
                            })
                          }
                          placeholder="e.g. terms-2026-09-09"
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </>
            ) : null}

            <Button
              type="button"
              onClick={() => saveLegal.mutate()}
              disabled={saveLegal.isPending}
            >
              Save legal settings
            </Button>
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
