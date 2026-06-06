import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { Building2, ChevronRight, MapPin, Users } from "lucide-react";
import { StatusBadge } from "@/components/detail/DetailLayout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { listBusinesses } from "@/lib/api";

export function ApprovedBusinessPage() {
  const { data = [], isLoading } = useQuery({
    queryKey: ["businesses"],
    queryFn: listBusinesses,
  });

  return (
    <div className="p-6">
      <div className="mx-auto max-w-4xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            Approved Businesses
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Browse all approved businesses on the platform. Select one to view
            full details, owner info, and locations.
          </p>
        </div>

        <Card>
          <CardHeader className="border-b">
            <CardTitle className="text-base">
              {isLoading ? "Loading..." : `${data.length} business${data.length === 1 ? "" : "es"}`}
            </CardTitle>
          </CardHeader>

          <CardContent className="p-0">
            {isLoading && (
              <div className="space-y-0 divide-y">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="animate-pulse p-4">
                    <div className="h-4 w-48 rounded bg-muted" />
                    <div className="mt-2 h-3 w-32 rounded bg-muted" />
                  </div>
                ))}
              </div>
            )}

            {!isLoading && data.length === 0 && (
              <div className="p-8 text-center">
                <Building2 className="mx-auto h-10 w-10 text-muted-foreground/50" />
                <p className="mt-3 font-medium">No businesses yet</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  Approved registrations will appear here.
                </p>
              </div>
            )}

            {!isLoading && data.length > 0 && (
              <div className="divide-y">
                {data.map((business) => (
                  <Link
                    key={business.id}
                    to={`/admin/approved-business/${business.id}`}
                    className="group flex items-center justify-between gap-4 p-4 transition-colors hover:bg-muted/40"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-medium">{business.name}</p>
                        <StatusBadge status={business.status} />
                      </div>
                      <p className="mt-1 font-mono text-sm text-muted-foreground">
                        {business.business_code}
                      </p>
                      <div className="mt-2 flex flex-wrap gap-4 text-xs text-muted-foreground">
                        <span className="inline-flex items-center gap-1">
                          <Users className="h-3.5 w-3.5" />
                          {business.employee_count} employees
                        </span>
                        <span className="inline-flex items-center gap-1">
                          <MapPin className="h-3.5 w-3.5" />
                          {business.location_count} location
                          {business.location_count === 1 ? "" : "s"}
                        </span>
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
