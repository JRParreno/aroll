import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { ChevronRight, ClipboardList, FileText, Mail, MapPin } from "lucide-react";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { listRegistrations } from "@/lib/api";
import { formatBusinessType } from "@/lib/registrationDocuments";

export function AdminRegistrationsPage() {
  const { data = [], isLoading } = useQuery({
    queryKey: ["registrations"],
    queryFn: () => listRegistrations("pending"),
  });

  return (
    <div className="p-6">
      <div className="mx-auto max-w-4xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            Pending Registration Requests
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Review new business sign-ups. Open a request to see full details and
            approve or reject it.
          </p>
        </div>

        <Card>
          <CardHeader className="border-b">
            <CardTitle className="text-base">
              {isLoading
                ? "Loading..."
                : `${data.length} pending request${data.length === 1 ? "" : "s"}`}
            </CardTitle>
          </CardHeader>

          <CardContent className="p-0">
            {isLoading && (
              <div className="divide-y">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="animate-pulse p-4">
                    <div className="h-4 w-48 rounded bg-muted" />
                    <div className="mt-2 h-3 w-64 rounded bg-muted" />
                  </div>
                ))}
              </div>
            )}

            {!isLoading && data.length === 0 && (
              <div className="p-8 text-center">
                <ClipboardList className="mx-auto h-10 w-10 text-muted-foreground/50" />
                <p className="mt-3 font-medium">All caught up</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  There are no pending registration requests right now.
                </p>
              </div>
            )}

            {!isLoading && data.length > 0 && (
              <div className="divide-y">
                {data.map((registration) => (
                  <Link
                    key={registration.id}
                    to={`/admin/registrations/${registration.id}`}
                    className="group flex items-center justify-between gap-4 p-4 transition-colors hover:bg-muted/40"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-medium">{registration.business_name}</p>
                        <StatusBadge status={registration.status} />
                      </div>
                      <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
                        <Mail className="h-3.5 w-3.5 shrink-0" />
                        {registration.owner_name} · {registration.owner_email}
                      </p>
                      <div className="mt-2 flex flex-wrap gap-4 text-xs text-muted-foreground">
                        <span>{formatBusinessType(registration.business_type)}</span>
                        <span className="inline-flex items-center gap-1">
                          <FileText className="h-3.5 w-3.5" />
                          {registration.documents.length} document
                          {registration.documents.length === 1 ? "" : "s"}
                        </span>
                        {registration.proposed_address && (
                          <span className="inline-flex items-center gap-1">
                            <MapPin className="h-3.5 w-3.5" />
                            {registration.proposed_address}
                          </span>
                        )}
                        <span>Submitted {formatDateTime(registration.submitted_at)}</span>
                      </div>
                    </div>
                    <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:text-foreground" />
                  </Link>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
