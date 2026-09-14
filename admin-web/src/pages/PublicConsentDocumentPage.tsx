import { useParams } from "react-router-dom";

const API_BASE =
  import.meta.env.VITE_API_URL ??
  (import.meta.env.DEV ? "/api/v1" : "http://localhost:8000/api/v1");

export function PublicConsentDocumentPage() {
  const { documentId = "" } = useParams();
  if (!documentId) {
    return (
      <main className="mx-auto max-w-2xl px-4 py-10 text-sm text-red-700">
        Consent document not found.
      </main>
    );
  }
  const src = `${API_BASE}/public/consents/${documentId}/page`;
  return (
    <iframe
      title="Consent document"
      src={src}
      className="min-h-screen w-full border-0 bg-[#F4F6F8]"
    />
  );
}
