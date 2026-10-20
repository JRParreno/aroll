import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { useParams } from "react-router-dom";
import { getPublicLegalPage } from "@/lib/api";
import { LegalDocumentBody } from "@/pages/legal/LegalDocumentBody";

function LegalState({
  children,
  tone = "muted",
}: {
  children: ReactNode;
  tone?: "muted" | "error";
}) {
  return (
    <main className="min-h-screen bg-[#F7F8FA] px-4 py-10">
      <p
        className={`mx-auto max-w-2xl text-sm ${
          tone === "error" ? "text-red-700" : "text-slate-600"
        }`}
      >
        {children}
      </p>
    </main>
  );
}

export function PublicLegalPage() {
  const { businessCode = "" } = useParams();
  const { data, isLoading, isError } = useQuery({
    queryKey: ["public-legal", businessCode],
    queryFn: () => getPublicLegalPage(businessCode),
    enabled: businessCode.length > 0,
  });

  if (isLoading) {
    return <LegalState>Loading workplace legal documents…</LegalState>;
  }

  if (isError || !data) {
    return (
      <LegalState tone="error">
        This workplace legal page could not be found.
      </LegalState>
    );
  }

  const sections = [data.terms, data.privacy, data.biometric];

  return (
    <main className="min-h-screen bg-[#F7F8FA] px-4 py-10 sm:py-12">
      <div className="mx-auto max-w-2xl">
        <p className="text-[0.72rem] font-bold uppercase tracking-[0.12em] text-slate-500">
          Workplace legal documents
        </p>
        <h1 className="mt-2 text-2xl font-semibold tracking-tight text-slate-900 sm:text-[1.65rem]">
          {data.business_name}
        </h1>
        <p className="mt-1 text-sm text-slate-500">
          Business code {data.business_code}
        </p>
        <p className="mt-3 max-w-xl text-sm leading-relaxed text-slate-600">
          These documents apply to this workplace. Terms, privacy, and biometric
          consent each have a different purpose. Read the document that matches
          the consent you are reviewing.
        </p>

        <div className="mt-8 space-y-4">
          {sections.map((section) => {
            const sourceLabel =
              section.content_source === "business_custom"
                ? "Custom for this workplace"
                : "Aroll+ default";
            const unpublished =
              section.content_source === "admin_default"
                ? `Aroll+ has not published ${section.title} yet.`
                : `${data.business_name} has not published ${section.title} yet. Contact your employer before using face enrollment or live attendance.`;
            return (
              <section
                key={section.consent_type}
                className="rounded-2xl border border-slate-200 bg-white px-5 py-5 sm:px-6 sm:py-6"
              >
                <h2 className="text-lg font-semibold tracking-tight text-slate-900">
                  {section.title}
                </h2>
                <p className="mt-1 text-sm text-slate-500">
                  {section.version
                    ? `Version ${section.version} · ${sourceLabel}`
                    : sourceLabel}
                </p>
                <div className="mt-4 border-t border-slate-100 pt-4">
                  <LegalDocumentBody
                    text={section.published ? section.content ?? "" : unpublished}
                  />
                </div>
              </section>
            );
          })}
        </div>
      </div>
    </main>
  );
}
