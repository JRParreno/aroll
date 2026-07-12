import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import {
  ChevronRight,
  ClipboardList,
  FileText,
  Mail,
  MapPin,
} from "lucide-react";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
    <div className="min-h-full bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-[#6B7280]">
            Verification queue
          </p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-[#1F2937] sm:text-3xl">
            Registration Requests
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
            Review pending business applications. Open a request to view
            documents and approve or reject the application.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
        <Card className="overflow-hidden rounded-2xl border-slate-200 bg-white shadow-sm">
          <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle className="text-base font-semibold text-[#1F2937]">
                  Pending Applications
                </CardTitle>
                <p className="mt-1 text-sm text-[#6B7280]">
                  {isLoading
                    ? "Loading registration requests..."
                    : `${data.length} pending request${data.length === 1 ? "" : "s"}`}
                </p>
              </div>
              <span className="rounded-full bg-amber-50 px-3 py-1 text-xs font-medium text-amber-700">
                Needs review
              </span>
            </div>
          </CardHeader>

          <CardContent className="p-0">
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
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-red-50 text-red-600">
                  <ClipboardList className="h-6 w-6" />
                </div>
                <p className="mt-4 font-medium text-[#1F2937]">
                  Unable to load registration requests
                </p>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Sign in as a platform admin and try again.
                </p>
              </div>
            )}

            {!isLoading && !isError && data.length === 0 && (
              <div className="px-6 py-14 text-center">
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#EAF2FB] text-[#1E3A5F]">
                  <ClipboardList className="h-6 w-6" />
                </div>
                <p className="mt-4 font-medium text-[#1F2937]">All caught up</p>
                <p className="mt-1 text-sm text-[#6B7280]">
                  There are no pending registration requests right now.
                </p>
              </div>
            )}

            {!isLoading && !isError && data.length > 0 && (
              <div>
                <div className="hidden grid-cols-[1.2fr_0.8fr_0.8fr_auto] gap-4 border-b border-slate-200 bg-white px-5 py-3 text-xs font-medium uppercase tracking-wide text-[#6B7280] md:grid">
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
                          <p className="truncate font-medium text-[#1F2937]">
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

                      <span className="inline-flex items-center justify-between gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-sm font-medium text-[#1E3A5F] transition group-hover:bg-[#D9EAFB] md:justify-center">
                        Review
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
