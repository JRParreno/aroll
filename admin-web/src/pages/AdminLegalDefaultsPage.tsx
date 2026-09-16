import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Scale } from "lucide-react";
import {
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
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
    <AdminPage>
      <AdminPageHeader
        eyebrow="Platform legal"
        title="Consents"
        description="Manage the ordered default consent documents for every workplace. Employees see these unless an owner turns on custom workplace consents. Saving generates a public webpage URL for each document."
      />

      <AdminPageContent>
        {isError ? (
          <p className="text-sm text-red-700">Consents could not be loaded.</p>
        ) : (
          <Card className="admin-card overflow-hidden rounded-[1.25rem] border-[#E8EEF5] bg-white shadow-none">
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
                  addButtonClassName="rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                  onChanged={() => {
                    qc.invalidateQueries({ queryKey: ["admin-consents"] });
                  }}
                />
              )}
            </CardContent>
          </Card>
        )}
      </AdminPageContent>
    </AdminPage>
  );
}
