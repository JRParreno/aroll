import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { getPublicLegalPage } from "@/lib/api";

export function PublicLegalPage() {
  const { businessCode = "" } = useParams();
  const { data, isLoading, isError } = useQuery({
    queryKey: ["public-legal", businessCode],
    queryFn: () => getPublicLegalPage(businessCode),
    enabled: businessCode.length > 0,
  });

  if (isLoading) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-10 text-sm text-slate-600">
        Loading workplace legal documents…
      </main>
    );
  }

  if (isError || !data) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-10 text-sm text-red-700">
        This workplace legal page could not be found.
      </main>
    );
  }

  const sections = [data.terms, data.privacy, data.biometric];

  return (
    <main className="mx-auto max-w-2xl px-4 py-10">
      <p className="text-xs font-semibold uppercase tracking-[0.14em] text-slate-500">
        Workplace legal documents
      </p>
      <h1 className="mt-2 text-2xl font-semibold text-slate-900">
        {data.business_name}
      </h1>
      <p className="mt-1 text-sm text-slate-500">
        Business code {data.business_code}
      </p>
      <div className="mt-6 space-y-4">
        {sections.map((section) => (
          <section
            key={section.consent_type}
            className="rounded-2xl border border-slate-200 bg-white p-5"
          >
            <h2 className="text-lg font-semibold text-slate-900">
              {section.title}
            </h2>
            {section.version ? (
              <p className="mt-1 text-sm text-slate-500">
                Version {section.version}
                {section.content_source === "business_custom"
                  ? " · Custom for this workplace"
                  : " · Aroll+ default"}
              </p>
            ) : (
              <p className="mt-1 text-sm text-slate-500">
                {section.content_source === "business_custom"
                  ? "Custom for this workplace"
                  : "Aroll+ default"}
              </p>
            )}
            <p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-slate-800">
              {section.published
                ? section.content
                : section.content_source === "admin_default"
                  ? `Aroll+ has not published ${section.title} yet.`
                  : `${data.business_name} has not published ${section.title} yet. Contact your employer before using face enrollment or live attendance.`}
            </p>
          </section>
        ))}
      </div>
    </main>
  );
}
