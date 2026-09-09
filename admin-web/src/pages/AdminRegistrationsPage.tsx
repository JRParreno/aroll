import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  ChevronRight,
  ClipboardList,
  FileText,
  Mail,
  MapPin,
} from "lucide-react";
import {
  AdminCard,
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { listRegistrations } from "@/lib/api";
import { formatBusinessType } from "@/lib/registrationDocuments";

export function AdminRegistrationsPage() {
  const { data = [], isLoading, isError } = useQuery({
    queryKey: ["registrations", "pending"],
    queryFn: () => listRegistrations("pending"),
    staleTime: 0,
    refetchOnWindowFocus: true,
  });

  return (
    <AdminPage>
      <AdminPageHeader
        eyebrow="Verification queue"
        title="Registration Requests"
        description="Review pending business applications. Open a request to view documents and approve or reject the application."
      />

      <AdminPageContent>
        <AdminCard className="overflow-hidden">
          <div className="border-b border-slate-200/80 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="owner-section-title">Pending Applications</h2>
                <p className="owner-section-subtitle mt-1">
                  {isLoading
                    ? "Loading registration requests..."
                    : `${data.length} pending request${data.length === 1 ? "" : "s"}`}
                </p>
              </div>
              <span className="rounded-full bg-amber-50 px-3 py-1 text-xs font-medium text-amber-700">
                Needs review
              </span>
            </div>
          </div>

          {isLoading && (
            <div className="divide-y divide-slate-100">
              {[1, 2, 3].map((i) => (
                <div key={i} className="animate-pulse p-5">
                  <div className="h-4 w-56 rounded bg-slate-200" />
                  <div className="mt-3 h-3 w-80 max-w-full rounded bg-slate-100" />
                </div>
              ))}
            </div>
          )}

          {!isLoading && isError && (
            <div className="px-6 py-14 text-center">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-xl bg-red-50 text-red-600">
                <ClipboardList className="h-6 w-6" />
              </div>
              <p className="owner-section-title mt-4">
                Unable to load registration requests
              </p>
              <p className="owner-section-subtitle mt-1">
                Sign in as a platform admin and try again.
              </p>
            </div>
          )}

          {!isLoading && !isError && data.length === 0 && (
            <div className="px-6 py-14 text-center">
              <div className="owner-icon-well mx-auto h-12 w-12">
                <ClipboardList className="h-6 w-6" />
              </div>
              <p className="owner-section-title mt-4">All caught up</p>
              <p className="owner-section-subtitle mt-1">
                There are no pending registration requests right now.
              </p>
            </div>
          )}

          {!isLoading && !isError && data.length > 0 && (
            <div>
              <div className="owner-label hidden grid-cols-[1.2fr_0.8fr_0.8fr_auto] gap-4 border-b border-slate-200 bg-white px-5 py-3 uppercase text-[#6B7280] md:grid">
                <span>Business</span>
                <span>Owner</span>
                <span>Submitted</span>
                <span className="text-right">Action</span>
              </div>

              <div className="divide-y divide-slate-100">
                {data.map((registration) => (
                  <Link
                    key={registration.id}
                    to={`/admin/registrations/${registration.id}`}
                    className="group grid gap-4 p-5 transition hover:bg-[#FAFBFC] md:grid-cols-[1.2fr_0.8fr_0.8fr_auto] md:items-center"
                  >
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="truncate text-[0.9375rem] font-medium text-[#1F2937]">
                          {registration.business_name}
                        </p>
                        <StatusBadge status={registration.application_status} />
                      </div>
                      <div className="mt-2 flex flex-wrap gap-3 text-sm text-[#6B7280]">
                        <span>{formatBusinessType(registration.business_type)}</span>
                        <span className="inline-flex items-center gap-1.5">
                          <FileText className="h-4 w-4" />
                          {registration.documents.length} document
                          {registration.documents.length === 1 ? "" : "s"}
                        </span>
                      </div>
                    </div>

                    <div className="min-w-0 text-sm text-[#6B7280]">
                      <p className="font-medium text-[#1F2937]">
                        {registration.owner_name}
                      </p>
                      <p className="mt-1 flex min-w-0 items-center gap-1.5">
                        <Mail className="h-4 w-4 shrink-0" />
                        <span className="truncate">
                          {registration.owner_email}
                        </span>
                      </p>
                      {registration.proposed_address && (
                        <p className="mt-1 flex min-w-0 items-center gap-1.5">
                          <MapPin className="h-4 w-4 shrink-0" />
                          <span className="truncate">
                            {registration.proposed_address}
                          </span>
                        </p>
                      )}
                    </div>

                    <p className="text-sm text-[#6B7280]">
                      {formatDateTime(registration.submitted_at)}
                    </p>

                    <span className="inline-flex items-center justify-between gap-2 rounded-xl bg-[#EAF2FB] px-4 py-2 text-sm font-medium text-[#1E3A5F] transition group-hover:bg-[#D9EAFB] md:justify-center">
                      Review
                      <ChevronRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
                    </span>
                  </Link>
                ))}
              </div>
            </div>
          )}
        </AdminCard>
      </AdminPageContent>
    </AdminPage>
  );
}
