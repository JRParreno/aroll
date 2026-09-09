import { Link, Navigate, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { SystemBrandPanel, SystemLogo } from "@/components/branding/SystemBranding";
import { AuthLegalLinks } from "@/components/legal/AuthLegalLinks";
import {
  LEGAL_DOCUMENTS,
  legalPlainText,
  type LegalDocumentSlug,
} from "@/lib/legalDocuments";

const SLUGS: LegalDocumentSlug[] = ["terms", "privacy", "biometric-consent"];

function isLegalSlug(value: string | undefined): value is LegalDocumentSlug {
  return SLUGS.includes(value as LegalDocumentSlug);
}

export function LegalDocumentPage() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();

  if (!isLegalSlug(slug)) {
    return <Navigate to="/legal/docs/terms" replace />;
  }

  const document = LEGAL_DOCUMENTS[slug];

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[minmax(300px,38vw)_1fr]">
      <SystemBrandPanel description="Face Recognition Attendance and Payroll" />

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
              Aroll+ legal
            </p>
            <h1 className="mt-2 text-2xl font-semibold tracking-tight text-[#111827] sm:text-3xl">
              {document.title}
            </h1>
            <p className="mt-3 text-sm leading-6 text-[#6B7280]">
              Aroll+ prototype reference document. Employee consent uses the
              workplace-configured webpage after login, not this file.
            </p>
            <div className="mt-6 whitespace-pre-wrap text-sm leading-7 text-[#111827]">
              {legalPlainText(document.markdown)}
            </div>
          </section>

          <div className="mt-5 flex flex-col items-center gap-3">
            <AuthLegalLinks />
            <Link
              to="/legal/docs/biometric-consent"
              className="text-xs font-medium text-[#1E3A5F] underline underline-offset-2"
            >
              Biometric / Face Consent
            </Link>
          </div>
        </div>
      </main>
    </div>
  );
}
