import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
} from "@/components/owner/layout/OwnerPageLayout";

type OwnerComingSoonProps = {
  title: string;
  backTo?: string;
  backLabel?: string;
};

export function OwnerComingSoon({
  title,
  backTo,
  backLabel = "Back",
}: OwnerComingSoonProps) {
  return (
    <OwnerPage>
      <OwnerPageContent>
        {backTo ? <OwnerPageBackLink to={backTo} label={backLabel} /> : null}
        <Card className="rounded-2xl border-slate-200 shadow-sm">
          <CardHeader>
            <CardTitle className="text-xl font-semibold text-[#1F2937]">
              {title}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-[#6B7280]">
              This module is ready for the next workflow pass.
            </p>
          </CardContent>
        </Card>
      </OwnerPageContent>
    </OwnerPage>
  );
}
