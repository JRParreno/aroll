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
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  fetchOwnerRegistrationDocumentFile,
  getBusinessSettings,
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
