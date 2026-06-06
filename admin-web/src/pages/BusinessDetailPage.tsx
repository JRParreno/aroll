import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
import {
  Building2,
  CalendarClock,
  Hash,
  Mail,
  MapPin,
  Phone,
  Users,
  Globe,
} from "lucide-react";
import {
  DetailField,
  DetailSection,
  EmptyState,
  formatDateTime,
  PageHeader,
  StatusBadge,
} from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
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
      <div className="p-6">
        <div className="animate-pulse space-y-4">
          <div className="h-4 w-32 rounded bg-muted" />
          <div className="h-8 w-64 rounded bg-muted" />
          <div className="h-40 rounded-xl bg-muted" />
        </div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-6">
        <EmptyState
          title="Business not found"
          description="This business may have been removed or the link is invalid."
        />
        <div className="mt-4">
          <Button asChild variant="outline">
            <Link to="/admin/approved-business">Back to approved businesses</Link>
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6">
      <div className="mx-auto max-w-4xl space-y-6">
        <PageHeader
          backTo="/admin/approved-business"
          backLabel="Approved businesses"
          title={data.name}
          description="Overview of this approved business, its owner, and configured locations."
          badge={<StatusBadge status={data.status} />}
        />

        <div className="grid gap-4 sm:grid-cols-3">
          <div className="rounded-xl border bg-card p-4 shadow-sm">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Business Code
            </p>
            <p className="mt-2 font-mono text-lg font-semibold">{data.business_code}</p>
          </div>
          <div className="rounded-xl border bg-card p-4 shadow-sm">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Active Employees
            </p>
            <p className="mt-2 text-lg font-semibold">{data.employee_count}</p>
          </div>
          <div className="rounded-xl border bg-card p-4 shadow-sm">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Locations
            </p>
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

            <section className="rounded-xl border bg-card p-5 shadow-sm sm:p-6">
              <div className="mb-5 flex items-start gap-3">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <MapPin className="h-4 w-4" />
                </div>
                <div>
                  <h2 className="text-base font-semibold">Work Locations</h2>
                  <p className="mt-1 text-sm text-muted-foreground">
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
                      className="rounded-lg border bg-muted/20 p-4"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <p className="font-medium">{loc.label}</p>
                        {loc.is_primary && (
                          <span className="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
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

            <section className="rounded-xl border bg-muted/30 p-5">
              <h2 className="text-sm font-semibold">Quick summary</h2>
              <ul className="mt-3 space-y-2 text-sm text-muted-foreground">
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
      </div>
    </div>
  );
}
