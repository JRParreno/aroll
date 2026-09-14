import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Scale } from "lucide-react";
import { ConsentDocumentManager } from "@/components/consents/ConsentDocumentManager";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { listConsentDocuments } from "@/lib/api";

export function AdminLegalDefaultsPage() {
  const qc = useQueryClient();
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin-consents"],
    queryFn: () => listConsentDocuments("admin"),
  });
  const documents = data?.documents ?? [];

  return (
    <div className="min-h-full bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-[#6B7280]">Platform legal</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-[#1F2937] sm:text-3xl">
            Consents
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
            Manage the ordered default consent documents for every workplace.
            Employees see these unless an owner turns on custom workplace
            consents. Each saved document gets a public webpage URL for the
            employee WebView.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
        <Card className="overflow-hidden rounded-2xl border-slate-200 bg-white shadow-sm">
          <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle className="flex items-center gap-2 text-base font-semibold text-[#1F2937]">
                  <Scale className="h-4 w-4" />
                  Platform consent documents
                </CardTitle>
                <p className="mt-1 text-sm text-[#6B7280]">
                  {isLoading
                    ? "Loading consents..."
                    : isError
                      ? "Unable to load consent documents"
                      : `${documents.length} document${documents.length === 1 ? "" : "s"}`}
                </p>
              </div>
              <span className="rounded-full bg-[#EAF2FB] px-3 py-1 text-xs font-medium text-[#1E3A5F]">
                Admin defaults
              </span>
            </div>
          </CardHeader>
          <CardContent className="p-5 sm:p-6">
            {isLoading ? (
              <div className="divide-y divide-slate-100 rounded-xl border border-slate-200">
                {[1, 2, 3].map((item) => (
                  <div key={item} className="animate-pulse p-5">
                    <div className="h-4 w-52 rounded bg-slate-200" />
                    <div className="mt-3 h-3 w-72 max-w-full rounded bg-slate-100" />
                  </div>
                ))}
              </div>
            ) : isError ? (
              <div className="px-6 py-14 text-center">
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-red-50 text-red-600">
                  <Scale className="h-6 w-6" />
                </div>
                <p className="mt-4 font-medium text-[#1F2937]">
                  Consents could not be loaded
                </p>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Sign in as a platform admin and try again.
                </p>
                <Button
                  type="button"
                  variant="outline"
                  className="mt-5"
                  onClick={() => void refetch()}
                >
                  Retry
                </Button>
              </div>
            ) : (
              <ConsentDocumentManager
                scope="admin"
                documents={documents}
                canEdit
                onChanged={() => {
                  qc.invalidateQueries({ queryKey: ["admin-consents"] });
                }}
              />
            )}
          </CardContent>
        </Card>
      </main>
    </div>
  );
}
