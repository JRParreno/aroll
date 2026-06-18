import { useQuery } from "@tanstack/react-query";
import { Building2, FileText, Mail, Phone, User } from "lucide-react";
import { Link } from "react-router-dom";
import { BusinessRegistrationDocumentsSection } from "@/components/business/BusinessRegistrationDocumentsSection";
import {
  DetailField,
  DetailSection,
  StatusBadge,
} from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import {
  fetchOwnerRegistrationDocumentFile,
  getBusinessSettings,
} from "@/lib/api";
import { formatBusinessType, formatVerificationStatus } from "@/lib/registrationDocuments";

async function fetchOwnerDocument(
  _registrationId: string,
  documentId: string
) {
  return fetchOwnerRegistrationDocumentFile(documentId);
}

export function OwnerBusinessSettingsPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["business-settings"],
    queryFn: getBusinessSettings,
  });

  if (isLoading) {
    return (
      <div className="min-h-full bg-muted/30 p-6">
        <p className="text-sm text-muted-foreground">Loading business settings…</p>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="min-h-full bg-muted/30 p-6">
        <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          Unable to load business settings. Please try again.
        </p>
      </div>
    );
  }

  const verificationStatus = data.application_status
    ? formatVerificationStatus(data.application_status)
    : null;

  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-4xl space-y-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-2xl font-semibold">Business Settings</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Business profile, registration details, and uploaded compliance
              documents.
            </p>
          </div>
          <Button variant="outline" asChild>
            <Link to="/owner/settings/account">Edit in Account Settings</Link>
          </Button>
        </div>

        <DetailSection
          title="Business Information"
          description="Core business profile details for your organization."
          icon={<Building2 className="h-4 w-4" />}
        >
          <DetailField label="Business Name" value={data.business_name} />
          <DetailField
            label="Business Type"
            value={formatBusinessType(data.business_type)}
          />
          <DetailField label="Business Address" value={data.address || "—"} />
          <DetailField label="Business Code" value={data.business_code} />
          {verificationStatus && (
            <DetailField
              label="Registration Status"
              value={<StatusBadge status={verificationStatus} />}
            />
          )}
        </DetailSection>

        <DetailSection
          title="Owner Information"
          description="Primary owner contact details from your registration."
          icon={<User className="h-4 w-4" />}
        >
          <DetailField label="Owner Name" value={data.owner_name ?? "—"} />
          <DetailField
            label="Email"
            value={
              <a
                href={`mailto:${data.owner_email}`}
                className="text-primary hover:underline"
              >
                {data.owner_email}
              </a>
            }
            icon={<Mail className="h-3.5 w-3.5" />}
          />
          <DetailField
            label="Phone"
            value={
              data.owner_phone ? (
                <a
                  href={`tel:${data.owner_phone}`}
                  className="text-primary hover:underline"
                >
                  {data.owner_phone}
                </a>
              ) : (
                "Not provided"
              )
            }
            icon={<Phone className="h-3.5 w-3.5" />}
          />
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
      </div>
    </div>
  );
}
