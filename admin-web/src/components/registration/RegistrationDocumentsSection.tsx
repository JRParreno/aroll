import { Download, Eye, FileText } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { formatDateTime } from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import {
  downloadBlob,
  fetchAdminRegistrationDocumentFile,
  previewBlob,
  type RegistrationDocument,
} from "@/lib/api";
import { DOCUMENT_LABELS, formatFileSize } from "@/lib/registrationDocuments";

type RegistrationDocumentsSectionProps = {
  registrationId: string;
  documents: RegistrationDocument[];
};

export function RegistrationDocumentsSection({
  registrationId,
  documents,
}: RegistrationDocumentsSectionProps) {
  const [loadingId, setLoadingId] = useState<string | null>(null);

  async function handleAction(
    document: RegistrationDocument,
    action: "preview" | "download"
  ) {
    setLoadingId(document.id);
    try {
      const blob = await fetchAdminRegistrationDocumentFile(
        registrationId,
        document.id
      );
      if (action === "preview") {
        previewBlob(blob);
      } else {
        downloadBlob(blob, document.original_filename);
      }
    } catch {
      toast.error(`Unable to ${action} document`);
    } finally {
      setLoadingId(null);
    }
  }

  if (documents.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">No documents uploaded yet.</p>
    );
  }

  return (
    <ul className="divide-y rounded-lg border">
      {documents.map((doc) => (
        <li
          key={doc.id}
          className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between"
        >
          <div className="flex min-w-0 items-start gap-3">
            <FileText className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
            <div className="min-w-0">
              <p className="font-medium">
                {DOCUMENT_LABELS[doc.document_type] ?? doc.document_type}
              </p>
              <p className="truncate text-sm text-muted-foreground">
                {doc.original_filename}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                {formatFileSize(doc.file_size)} · Uploaded{" "}
                {formatDateTime(doc.uploaded_at)}
              </p>
            </div>
          </div>
          <div className="flex shrink-0 gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={loadingId === doc.id}
              onClick={() => void handleAction(doc, "preview")}
            >
              <Eye className="mr-1.5 h-3.5 w-3.5" />
              Preview
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={loadingId === doc.id}
              onClick={() => void handleAction(doc, "download")}
            >
              <Download className="mr-1.5 h-3.5 w-3.5" />
              Download
            </Button>
          </div>
        </li>
      ))}
    </ul>
  );
}
