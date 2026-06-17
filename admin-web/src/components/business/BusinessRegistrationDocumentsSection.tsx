import { Download, Eye, FileText } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { formatDateTime } from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  downloadBlob,
  fetchAdminRegistrationDocumentFile,
  previewBlob,
  type RegistrationDocument,
} from "@/lib/api";
import { DOCUMENT_FIELDS } from "@/lib/registrationDocuments";

const BUSINESS_DOCUMENT_LABELS: Record<string, string> = {
  business_permit: "Business Permit",
  valid_id: "Valid ID of Owner",
  dti_sec: "DTI / SEC Registration",
  bir_cor: "BIR Certificate of Registration",
};

function isPdfDocument(document: RegistrationDocument) {
  return (
    document.content_type === "application/pdf" ||
    document.original_filename.toLowerCase().endsWith(".pdf")
  );
}

function isImageDocument(document: RegistrationDocument) {
  return (
    document.content_type.startsWith("image/") ||
    /\.(jpg|jpeg|png)$/i.test(document.original_filename)
  );
}

type BusinessRegistrationDocumentsSectionProps = {
  registrationId: string | null;
  documents: RegistrationDocument[];
};

type ImagePreviewState = {
  title: string;
  filename: string;
  url: string;
};

export function BusinessRegistrationDocumentsSection({
  registrationId,
  documents,
}: BusinessRegistrationDocumentsSectionProps) {
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const [imagePreview, setImagePreview] = useState<ImagePreviewState | null>(
    null
  );

  useEffect(() => {
    return () => {
      if (imagePreview?.url) {
        URL.revokeObjectURL(imagePreview.url);
      }
    };
  }, [imagePreview?.url]);

  const documentsByType = Object.fromEntries(
    documents.map((document) => [document.document_type, document])
  );

  if (!registrationId || documents.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No registration documents available.
      </p>
    );
  }

  async function handleView(document: RegistrationDocument) {
    if (!registrationId) return;

    setLoadingId(document.id);
    try {
      const blob = await fetchAdminRegistrationDocumentFile(
        registrationId,
        document.id
      );

      if (isPdfDocument(document)) {
        previewBlob(blob);
        return;
      }

      if (isImageDocument(document)) {
        if (imagePreview?.url) {
          URL.revokeObjectURL(imagePreview.url);
        }
        setImagePreview({
          title:
            BUSINESS_DOCUMENT_LABELS[document.document_type] ??
            document.document_type,
          filename: document.original_filename,
          url: URL.createObjectURL(blob),
        });
        return;
      }

      previewBlob(blob);
    } catch {
      toast.error("Unable to view document");
    } finally {
      setLoadingId(null);
    }
  }

  async function handleDownload(document: RegistrationDocument) {
    if (!registrationId) return;

    setLoadingId(document.id);
    try {
      const blob = await fetchAdminRegistrationDocumentFile(
        registrationId,
        document.id
      );
      downloadBlob(blob, document.original_filename);
    } catch {
      toast.error("Unable to download document");
    } finally {
      setLoadingId(null);
    }
  }

  function closeImagePreview(open: boolean) {
    if (!open && imagePreview?.url) {
      URL.revokeObjectURL(imagePreview.url);
      setImagePreview(null);
    }
  }

  return (
    <>
      <div className="space-y-4 sm:col-span-2">
        {DOCUMENT_FIELDS.map((field) => {
          const document = documentsByType[field.key];

          return (
            <div
              key={field.key}
              className="rounded-lg border bg-muted/20 p-4"
            >
              <div className="flex items-start gap-3">
                <FileText className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                <div className="min-w-0 flex-1">
                  <p className="font-medium">
                    {BUSINESS_DOCUMENT_LABELS[field.key] ?? field.label}
                  </p>
                  {document ? (
                    <>
                      <div className="mt-3 grid gap-3 sm:grid-cols-2">
                        <div>
                          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                            File Name
                          </p>
                          <p className="mt-1 break-all text-sm">
                            {document.original_filename}
                          </p>
                        </div>
                        <div>
                          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                            Upload Date
                          </p>
                          <p className="mt-1 text-sm">
                            {formatDateTime(document.uploaded_at)}
                          </p>
                        </div>
                      </div>
                      <div className="mt-4 flex flex-wrap gap-2">
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          disabled={loadingId === document.id}
                          onClick={() => void handleView(document)}
                        >
                          <Eye className="mr-1.5 h-3.5 w-3.5" />
                          View
                        </Button>
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          disabled={loadingId === document.id}
                          onClick={() => void handleDownload(document)}
                        >
                          <Download className="mr-1.5 h-3.5 w-3.5" />
                          Download
                        </Button>
                      </div>
                    </>
                  ) : (
                    <p className="mt-2 text-sm text-muted-foreground">
                      Not uploaded
                    </p>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      <Dialog open={Boolean(imagePreview)} onOpenChange={closeImagePreview}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>{imagePreview?.title}</DialogTitle>
          </DialogHeader>
          {imagePreview && (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">
                {imagePreview.filename}
              </p>
              <img
                src={imagePreview.url}
                alt={imagePreview.filename}
                className="max-h-[70vh] w-full rounded-md border object-contain"
              />
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
