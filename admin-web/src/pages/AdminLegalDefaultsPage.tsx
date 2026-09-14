import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Scale } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ConsentDocumentManager } from "@/components/consents/ConsentDocumentManager";
import { listConsentDocuments } from "@/lib/api";

export function AdminLegalDefaultsPage() {
  const qc = useQueryClient();
  const { data, isLoading, isError } = useQuery({
    queryKey: ["admin-consents"],
    queryFn: () => listConsentDocuments("admin"),
  });

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
            consents. Saving generates a public webpage URL for each document.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
        {isError ? (
          <p className="text-sm text-red-700">Consents could not be loaded.</p>
        ) : (
          <Card className="overflow-hidden rounded-2xl border-slate-200 bg-white shadow-sm">
            <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
              <CardTitle className="flex items-center gap-2 text-base font-semibold text-[#1F2937]">
                <Scale className="h-4 w-4" />
                Platform consent documents
              </CardTitle>
            </CardHeader>
            <CardContent className="p-5 sm:p-6">
              {isLoading ? (
                <p className="text-sm text-[#6B7280]">Loading consents…</p>
              ) : (
                <ConsentDocumentManager
                  scope="admin"
                  documents={data?.documents ?? []}
                  canEdit
                  onChanged={() => {
                    qc.invalidateQueries({ queryKey: ["admin-consents"] });
                  }}
                />
              )}
            </CardContent>
          </Card>
        )}
      </main>
    </div>
  );
}
