import { useParams } from "react-router-dom";

const API_BASE = import.meta.env.VITE_API_URL ?? "/api/v1";

export function PublicConsentDocumentPage() {
  const { documentId = "" } = useParams();
  if (!documentId) {
    return (
      <main className="min-h-screen bg-[#F7F8FA] px-4 py-10">
        <p className="mx-auto max-w-2xl text-sm text-red-700">
          Consent document not found.
        </p>
      </main>
    );
  }
  const src = `${API_BASE}/public/consents/${documentId}/page`;
  return (
    <main className="min-h-screen bg-[#F7F8FA]">
      <iframe
        title="Consent document"
        src={src}
        className="min-h-screen w-full border-0 bg-[#F7F8FA]"
      />
    </main>
  );
}
