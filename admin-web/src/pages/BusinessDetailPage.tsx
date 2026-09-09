import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import {
  Building2,
  CalendarClock,
  FileText,
  Hash,
  Mail,
  MapPin,
  Phone,
  Users,
  Globe,
} from "lucide-react";
import {
  AdminPage,
  AdminPageBackLink,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import {
  DetailField,
  DetailSection,
  EmptyState,
  formatDateTime,
  StatusBadge,
} from "@/components/detail/DetailLayout";
import { BusinessRegistrationDocumentsSection } from "@/components/business/BusinessRegistrationDocumentsSection";
import { TenantKindBadge } from "@/components/tenant/SimulatedBadge";
import { getBusiness } from "@/lib/api";

export function BusinessDetailPage() {
  const { id } = useParams<{ id: string }>();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["business", id],
    queryFn: () => getBusiness(id!),
    enabled: Boolean(id),
  });

  if (isLoading) {
    return (
      <AdminPage>
        <AdminPageHeader
          title="Business profile"
          description="Loading business details."
        />
        <AdminPageContent>
          <div className="animate-pulse space-y-4">
            <div className="h-4 w-32 rounded bg-muted" />
            <div className="h-8 w-64 rounded bg-muted" />
            <div className="h-40 rounded-2xl bg-muted" />
          </div>
        </AdminPageContent>
      </AdminPage>
    );
  }

  if (isError || !data) {
    return (
      <AdminPage>
        <AdminPageHeader
          title="Business not found"
          description="This business may have been removed or the link is invalid."
        />
        <AdminPageContent>
          <AdminPageBackLink
            to="/admin/approved-business"
            label="Back to approved businesses"
          />
        </AdminPageContent>
      </AdminPage>
    );
  }

  return (
    <AdminPage>
      <AdminPageHeader
        title={data.name}
        description="Overview of this approved business, its owner, and configured locations."
        actions={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={data.status} />
            <TenantKindBadge
              isDemo={data.is_demo}
              isInternalTest={data.is_internal_test}
            />
          </span>
        }
      />

      <AdminPageContent>
        <AdminPageBackLink
          to="/admin/approved-business"
          label="Approved businesses"
        />

        <div className="grid gap-4 sm:grid-cols-3">
          <div className="owner-card p-4">
            <p className="owner-label uppercase text-[#6B7280]">Business Code</p>
            <p className="mt-2 font-mono text-lg font-semibold">{data.business_code}</p>
          </div>
          <div className="owner-card p-4">
            <p className="owner-label uppercase text-[#6B7280]">Active Employees</p>
            <p className="mt-2 text-lg font-semibold">{data.employee_count}</p>
          </div>
          <div className="owner-card p-4">
            <p className="owner-label uppercase text-[#6B7280]">Locations</p>
            <p className="mt-2 text-lg font-semibold">{data.locations.length}</p>
          </div>
        </div>

        <div className="grid gap-6 lg:grid-cols-3">
          <div className="space-y-6 lg:col-span-2">
            <DetailSection
              title="Business Profile"
              description="Core account information for this business."
              icon={<Building2 className="h-4 w-4" />}
            >
              <DetailField
                label="Business Name"
                value={data.name}
                icon={<Building2 className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Business Code"
                value={
                  <span className="font-mono">{data.business_code}</span>
                }
                icon={<Hash className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Timezone"
                value={data.timezone}
                icon={<Globe className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Status"
                value={<StatusBadge status={data.status} />}
              />
              {(data.is_demo || data.is_internal_test) && (
                <DetailField
                  label="Account type"
                  value={
                    <TenantKindBadge
                      isDemo={data.is_demo}
                      isInternalTest={data.is_internal_test}
                    />
                  }
                />
              )}
            </DetailSection>

            {data.owner && (
              <DetailSection
                title="Owner"
                description="Primary owner from the original registration."
                icon={<Users className="h-4 w-4" />}
              >
                <DetailField label="Name" value={data.owner.name} />
                <DetailField
                  label="Email"
                  value={
                    <a
                      href={`mailto:${data.owner.email}`}
                      className="text-primary hover:underline"
                    >
                      {data.owner.email}
                    </a>
                  }
                  icon={<Mail className="h-3.5 w-3.5" />}
                />
                <DetailField
                  label="Phone"
                  value={
                    data.owner.phone ? (
                      <a
                        href={`tel:${data.owner.phone}`}
                        className="text-primary hover:underline"
                      >
                        {data.owner.phone}
                      </a>
                    ) : (
                      "Not provided"
                    )
                  }
                  icon={<Phone className="h-3.5 w-3.5" />}
                />
              </DetailSection>
            )}

            <DetailSection
              title="Registration Documents"
              description="Official compliance documents submitted during registration."
              icon={<FileText className="h-4 w-4" />}
            >
              <BusinessRegistrationDocumentsSection
                registrationId={data.registration_id}
                documents={data.registration_documents}
              />
            </DetailSection>

            <section className="owner-card p-5 sm:p-6">
              <div className="mb-5 flex items-start gap-3">
                <div className="owner-icon-well h-9 w-9 shrink-0">
                  <MapPin className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="owner-section-title">Work Locations</h2>
                  <p className="owner-section-subtitle mt-1">
                    Sites configured for attendance and geofencing.
                  </p>
                </div>
              </div>

              {data.locations.length === 0 ? (
                <EmptyState
                  title="No locations yet"
                  description="The owner has not set up a business location. They can add one after logging in."
                />
              ) : (
                <div className="space-y-3">
                  {data.locations.map((loc) => (
                    <div
                      key={loc.id}
                      className="rounded-xl border border-slate-200 bg-[#FAFBFC] p-4"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <p className="font-medium">{loc.label}</p>
                        {loc.is_primary && (
                          <span className="rounded-full bg-[#EAF2FB] px-2 py-0.5 text-xs font-medium text-[#1E3A5F]">
                            Primary
                          </span>
                        )}
                      </div>
                      <p className="mt-2 text-sm text-muted-foreground">
                        {loc.address}
                      </p>
                      <div className="mt-3 flex flex-wrap gap-4 text-xs text-muted-foreground">
                        {loc.latitude != null && loc.longitude != null && (
                          <span>
                            Coordinates: {loc.latitude.toFixed(5)},{" "}
                            {loc.longitude.toFixed(5)}
                          </span>
                        )}
                        <span>Geofence: {loc.geofence_radius_m}m</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>

          <div className="space-y-6">
            <DetailSection
              title="Timeline"
              description="Important dates for this business."
              icon={<CalendarClock className="h-4 w-4" />}
            >
              <DetailField
                label="Approved / Created"
                value={formatDateTime(data.created_at)}
                className="sm:col-span-2"
              />
              {data.registration_submitted_at && (
                <DetailField
                  label="Originally Submitted"
                  value={formatDateTime(data.registration_submitted_at)}
                  className="sm:col-span-2"
                />
              )}
            </DetailSection>

            <section className="owner-card-muted p-5">
              <h2 className="text-sm font-medium text-[#1F2937]">Quick summary</h2>
              <ul className="owner-section-subtitle mt-3 space-y-2 text-sm">
                <li>
                  • {data.employee_count} active employee
                  {data.employee_count === 1 ? "" : "s"} enrolled
                </li>
                <li>
                  • {data.locations.length} location
                  {data.locations.length === 1 ? "" : "s"} configured
                </li>
                <li>• Operating in {data.timezone}</li>
              </ul>
            </section>
          </div>
        </div>
      </AdminPageContent>
    </AdminPage>
  );
}
