import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { Building2, ChevronRight, MapPin, Users } from "lucide-react";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { listBusinesses } from "@/lib/api";

export function ApprovedBusinessPage() {
  const { data = [], isLoading } = useQuery({
    queryKey: ["businesses"],
    queryFn: listBusinesses,
  });

  return (
    <div className="min-h-full bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-[#6B7280]">
            Business directory
          </p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-[#1F2937] sm:text-3xl">
            Approved Businesses
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
            Browse approved businesses on the platform and open a profile to
            review owner, employee, and location details.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
        <Card className="overflow-hidden rounded-2xl border-slate-200 bg-white shadow-sm">
          <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle className="text-base font-semibold text-[#1F2937]">
                  Business List
                </CardTitle>
                <p className="mt-1 text-sm text-[#6B7280]">
                  {isLoading
                    ? "Loading approved businesses..."
                    : `${data.length} business${data.length === 1 ? "" : "es"} found`}
                </p>
              </div>
              <span className="rounded-full bg-[#EAF2FB] px-3 py-1 text-xs font-medium text-[#1E3A5F]">
                Approved
              </span>
            </div>
          </CardHeader>

          <CardContent className="p-0">
            {isLoading && (
              <div className="divide-y divide-slate-100">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="animate-pulse p-5">
                    <div className="h-4 w-52 rounded bg-slate-200" />
                    <div className="mt-3 h-3 w-72 rounded bg-slate-100" />
                  </div>
                ))}
              </div>
            )}

            {!isLoading && data.length === 0 && (
              <div className="px-6 py-14 text-center">
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#EAF2FB] text-[#1E3A5F]">
                  <Building2 className="h-6 w-6" />
                </div>
                <p className="mt-4 font-medium text-[#1F2937]">
                  No businesses yet
                </p>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Approved registrations will appear here.
                </p>
              </div>
            )}

            {!isLoading && data.length > 0 && (
              <div>
                <div className="hidden grid-cols-[1.2fr_0.8fr_0.8fr_auto] gap-4 border-b border-slate-200 bg-white px-5 py-3 text-xs font-medium uppercase tracking-wide text-[#6B7280] md:grid">
                  <span>Business</span>
                  <span>Usage</span>
                  <span>Created</span>
                  <span className="text-right">Action</span>
                </div>

                <div className="divide-y divide-slate-100">
                  {data.map((business) => (
                    <Link
                      key={business.id}
                      to={`/admin/approved-business/${business.id}`}
                      className="group grid gap-4 p-5 transition hover:bg-[#FAFBFC] md:grid-cols-[1.2fr_0.8fr_0.8fr_auto] md:items-center"
                    >
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="truncate font-medium text-[#1F2937]">
                            {business.name}
                          </p>
                          <StatusBadge status={business.status} />
                        </div>
                        <p className="mt-1 font-mono text-sm text-[#6B7280]">
                          {business.business_code}
                        </p>
                      </div>

                      <div className="flex flex-wrap gap-4 text-sm text-[#6B7280] md:block md:space-y-1">
                        <span className="inline-flex items-center gap-1.5">
                          <Users className="h-4 w-4" />
                          {business.employee_count} employees
                        </span>
                        <span className="inline-flex items-center gap-1.5 md:flex">
                          <MapPin className="h-4 w-4" />
                          {business.location_count} location
                          {business.location_count === 1 ? "" : "s"}
                        </span>
                      </div>

                      <p className="text-sm text-[#6B7280]">
                        {formatDateTime(business.created_at)}
                      </p>

                      <span className="inline-flex items-center justify-between gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-sm font-medium text-[#1E3A5F] transition group-hover:bg-[#D9EAFB] md:justify-center">
                        View Profile
                        <ChevronRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
                      </span>
                    </Link>
                  ))}
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </main>
    </div>
  );
}
