import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { ConsentDocumentManager } from "@/components/consents/ConsentDocumentManager";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  getBusinessLegalSettings,
  listConsentDocuments,
  updateBusinessLegalSettings,
} from "@/lib/api";

export function OwnerConsentConfigurationPage() {
  const qc = useQueryClient();
  const [useCustomConsents, setUseCustomConsents] = useState(false);

  const { data: legalData, isLoading: legalLoading } = useQuery({
    queryKey: ["business-legal"],
    queryFn: getBusinessLegalSettings,
  });
  const { data: consentCatalog, isLoading: consentsLoading } = useQuery({
    queryKey: ["owner-consents"],
    queryFn: () => listConsentDocuments("owner"),
  });

  useEffect(() => {
    if (!legalData) return;
    setUseCustomConsents(legalData.use_custom_consents);
  }, [legalData]);

  const saveLegal = useMutation({
    mutationFn: () =>
      updateBusinessLegalSettings({
        use_custom_consents: useCustomConsents,
      }),
    onSuccess: () => {
      toast.success("Consent settings saved");
      qc.invalidateQueries({ queryKey: ["business-legal"] });
      qc.invalidateQueries({ queryKey: ["owner-consents"] });
    },
    onError: () => toast.error("Failed to save consent settings"),
  });

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Consent Configuration"
        description="Manage workplace consent documents employees review and accept."
      />
      <OwnerPageContent className="max-w-4xl">
        <OwnerPageBackLink to="/owner/settings/setup" label="Back to Business Setup" />

        <Card>
          <CardHeader>
            <CardTitle className="text-[1.0625rem] font-semibold leading-snug tracking-[-0.015em]">
              Workplace consents
            </CardTitle>
            <p className="owner-section-subtitle mt-1">
              Employees always load consents from the API. This workplace uses
              Aroll+ Admin defaults unless you enable custom workplace consents.
            </p>
          </CardHeader>
          <CardContent className="space-y-4">
            {legalLoading ? (
              <p className="text-sm text-muted-foreground">Loading consent settings…</p>
            ) : (
              <>
                <label className="flex items-start gap-3 rounded-lg border border-slate-200 px-3 py-3 text-sm">
                  <input
                    type="checkbox"
                    className="mt-1"
                    checked={useCustomConsents}
                    onChange={(event) => setUseCustomConsents(event.target.checked)}
                  />
                  <span>
                    <span className="font-medium">Use custom workplace consents</span>
                    <span className="mt-1 block text-muted-foreground">
                      Off by default. When on, employees see only this workplace’s
                      documents. Incomplete or unpublished custom catalogs fail
                      closed and do not fall back to Admin defaults.
                    </span>
                  </span>
                </label>
                <Button
                  type="button"
                  onClick={() => saveLegal.mutate()}
                  disabled={saveLegal.isPending}
                >
                  {saveLegal.isPending ? "Saving…" : "Save consent toggle"}
                </Button>
              </>
            )}
            {consentsLoading ? (
              <p className="text-sm text-muted-foreground">Loading consents…</p>
            ) : useCustomConsents ? (
              <ConsentDocumentManager
                scope="owner"
                documents={consentCatalog?.documents ?? []}
                canEdit={consentCatalog?.can_edit === true}
                onChanged={() => {
                  qc.invalidateQueries({ queryKey: ["owner-consents"] });
                }}
              />
            ) : (
              <ConsentDocumentManager
                scope="owner"
                documents={consentCatalog?.documents ?? []}
                canEdit={false}
                readOnlyHint="Admin defaults apply. Turn on custom workplace consents to upload or edit documents for this workplace only."
                onChanged={() => {
                  qc.invalidateQueries({ queryKey: ["owner-consents"] });
                }}
              />
            )}
          </CardContent>
        </Card>
      </OwnerPageContent>
    </OwnerPage>
  );
}
