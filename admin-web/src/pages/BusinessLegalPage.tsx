import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { SystemBrandPanel, SystemLogo } from "@/components/branding/SystemBranding";
import { getPublicLegalPage } from "@/lib/api";

export function BusinessLegalPage() {
  const { businessCode } = useParams<{ businessCode: string }>();
  const navigate = useNavigate();
  const code = (businessCode ?? "").trim().toUpperCase();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["public-legal", code],
    queryFn: () => getPublicLegalPage(code),
    enabled: code.length > 0,
  });

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[minmax(300px,38vw)_1fr]">
      <SystemBrandPanel description="Workplace consent, terms, and privacy" />

      <main className="min-h-screen px-5 py-8 sm:px-8 lg:px-12">
        <div className="mx-auto w-full max-w-2xl">
          <div className="mb-6 lg:hidden">
            <SystemLogo className="h-auto w-40 max-w-full" />
          </div>

          <button
            type="button"
            onClick={() => {
              if (window.history.length > 1) navigate(-1);
              else navigate("/owner-login");
            }}
            className="mb-6 inline-flex items-center gap-2 text-sm font-medium text-[#6B7280] transition-colors hover:text-[#1E3A5F]"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>

          <section className="rounded-3xl border border-white/70 bg-white/80 p-5 shadow-sm backdrop-blur sm:p-7">
            <p className="text-xs font-medium uppercase tracking-[0.14em] text-[#6B7280]">
              Workplace consent
            </p>
            {isLoading ? (
              <p className="mt-4 text-sm text-[#6B7280]">Loading consent page…</p>
            ) : isError || !data ? (
              <div className="mt-4">
                <h1 className="text-2xl font-semibold tracking-tight text-[#111827]">
                  Consent page not found
                </h1>
                <p className="mt-3 text-sm leading-6 text-[#6B7280]">
                  This business has not published a consent webpage, or the
                  link is incorrect.
                </p>
              </div>
            ) : (
              <>
                <h1 className="mt-2 text-2xl font-semibold tracking-tight text-[#111827] sm:text-3xl">
                  {data.business_name}
                </h1>
                <p className="mt-3 text-sm leading-6 text-[#6B7280]">
                  Business code {data.business_code}. This page is configured
                  by the business owner. Opening it does not record agreement
                  by itself.
                </p>
                <div className="mt-6 whitespace-pre-wrap text-sm leading-7 text-[#111827]">
                  {data.content}
                </div>
              </>
            )}
          </section>

          <p className="mt-5 text-center text-xs text-[#6B7280]">
            Aroll+ prototype reference documents are on the{" "}
            <Link
              to="/legal/docs/terms"
              className="font-medium text-[#1E3A5F] underline underline-offset-2"
            >
              Aroll+ legal pages
            </Link>
            .
          </p>
        </div>
      </main>
    </div>
  );
}
