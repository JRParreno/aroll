import { Construction } from "lucide-react";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
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
      <OwnerPageHeader
        eyebrow="Coming soon"
        title={title}
        description="This module is prepared for the next workflow pass."
      />
      <OwnerPageContent>
        {backTo ? <OwnerPageBackLink to={backTo} label={backLabel} /> : null}
        <OwnerCard className="flex flex-col items-start gap-4 p-6 sm:flex-row sm:items-center">
          <div className="owner-icon-well h-12 w-12">
            <Construction className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-base font-semibold text-[#1F2937]">{title}</h2>
            <p className="mt-1 max-w-xl text-sm leading-relaxed text-[#6B7280]">
              We’re shaping this area to match the rest of your workspace. Check
              back soon for the full experience.
            </p>
          </div>
        </OwnerCard>
      </OwnerPageContent>
    </OwnerPage>
  );
}
