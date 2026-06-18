import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { AlertCircle } from "lucide-react";
import { toast } from "sonner";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  getRegistrationByEmail,
  resubmitRegistrationApplication,
  uploadRegistrationDocument,
} from "@/lib/api";
import {
  DOCUMENT_FIELDS,
  formatBusinessType,
  type DocumentKey,
} from "@/lib/registrationDocuments";

const ACCEPTED_FILE_TYPES = ".pdf,.jpg,.jpeg,.png";

type DocumentFiles = Record<DocumentKey, File | null>;

function isAcceptedFile(file: File) {
  const name = file.name.toLowerCase();
  return (
    file.type === "application/pdf" ||
    file.type === "image/jpeg" ||
    file.type === "image/png" ||
    name.endsWith(".pdf") ||
    name.endsWith(".jpg") ||
    name.endsWith(".jpeg") ||
    name.endsWith(".png")
  );
}

type DocumentUploadFieldProps = {
  id: string;
  label: string;
  existingFilename?: string;
  file: File | null;
  error?: string;
  onChange: (file: File | null) => void;
};

function DocumentUploadField({
  id,
  label,
  existingFilename,
  file,
  error,
  onChange,
}: DocumentUploadFieldProps) {
  const [typeError, setTypeError] = useState<string | null>(null);

  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      {existingFilename && !file && (
        <p className="text-xs text-muted-foreground">
          Current file: {existingFilename}
        </p>
      )}
      <Input
        id={id}
        type="file"
        accept={ACCEPTED_FILE_TYPES}
        className="cursor-pointer"
        onChange={(e) => {
          const selected = e.target.files?.[0] ?? null;
          if (selected && !isAcceptedFile(selected)) {
            setTypeError("File must be PDF, JPG, JPEG, or PNG");
            onChange(null);
            return;
          }
          setTypeError(null);
          onChange(selected);
        }}
      />
      {file ? (
        <p className="text-sm text-foreground">New upload: {file.name}</p>
      ) : (
        <p className="text-xs text-muted-foreground">
          Accepted formats: PDF, JPG, JPEG, PNG
        </p>
      )}
      {typeError && <p className="text-sm text-red-600">{typeError}</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}

export function RejectedApplicationPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [searchParams] = useSearchParams();
  const email = searchParams.get("email")?.trim() ?? "";

  const [documents, setDocuments] = useState<DocumentFiles>({
    business_permit: null,
    valid_id: null,
    dti_sec: null,
    bir_cor: null,
  });
  const [documentErrors, setDocumentErrors] = useState<
    Partial<Record<DocumentKey, string>>
  >({});

  const { data, isLoading, isError } = useQuery({
    queryKey: ["registration-by-email", email],
    queryFn: () => getRegistrationByEmail(email),
    enabled: email.length > 0,
    retry: false,
  });

  const resubmit = useMutation({
    mutationFn: async () => {
      if (!data) throw new Error("No registration loaded");

      for (const field of DOCUMENT_FIELDS) {
        const file = documents[field.key];
        if (file) {
          await uploadRegistrationDocument(data.id, field.key, file);
        }
      }

      return resubmitRegistrationApplication(data.id);
    },
    onSuccess: () => {
      toast.success("Application resubmitted for review");
      qc.invalidateQueries({ queryKey: ["registration-by-email", email] });
      navigate(
        `/pending-verification?email=${encodeURIComponent(email)}`
      );
    },
    onError: () => {
      toast.error("Failed to resubmit. Ensure all required documents are uploaded.");
    },
  });

  function validateDocuments() {
    if (!data) return false;

    const errors: Partial<Record<DocumentKey, string>> = {};
    const existingTypes = new Set(data.documents.map((doc) => doc.document_type));

    for (const field of DOCUMENT_FIELDS) {
      const hasExisting = existingTypes.has(field.key);
      const hasNewUpload = Boolean(documents[field.key]);
      if (!hasExisting && !hasNewUpload) {
        errors[field.key] = `${field.label} is required`;
      }
    }

    setDocumentErrors(errors);
    return Object.keys(errors).length === 0;
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!validateDocuments()) return;
    resubmit.mutate();
  }

  function updateDocument(key: DocumentKey, file: File | null) {
    setDocuments((current) => ({ ...current, [key]: file }));
    if (file) {
      setDocumentErrors((current) => {
        const next = { ...current };
        delete next[key];
        return next;
      });
    }
  }

  if (!email) {
    return (
      <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
        <div className="mx-auto max-w-xl">
          <Card>
            <CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">
                No email address provided. Return to registration to continue.
              </p>
              <Button asChild className="mt-4" variant="outline">
                <Link to="/register-business">Back to Registration</Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
        <div className="mx-auto max-w-xl">
          <Card>
            <CardContent className="pt-6 text-sm text-muted-foreground">
              Loading application details…
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
        <div className="mx-auto max-w-xl">
          <Card>
            <CardContent className="space-y-4 pt-6">
              <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                No rejected application found for this email address.
              </p>
              <Button asChild variant="outline">
                <Link to="/register-business">Start Registration</Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  if (data.application_status !== "rejected") {
    const redirectPath =
      data.application_status === "pending"
        ? `/pending-verification?email=${encodeURIComponent(email)}`
        : "/register-business";

    return (
      <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
        <div className="mx-auto max-w-xl">
          <Card>
            <CardContent className="space-y-4 pt-6">
              <p className="text-sm text-muted-foreground">
                This application is not in a rejected state.
              </p>
              <Button asChild variant="outline">
                <Link to={redirectPath}>Continue</Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  const existingByType = Object.fromEntries(
    data.documents.map((doc) => [doc.document_type, doc.original_filename])
  );

  return (
    <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
      <div className="mx-auto flex max-w-xl flex-col gap-6">
        <div>
          <h1 className="text-2xl font-semibold">Application Not Approved</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Update your documents and resubmit without re-entering business
            information.
          </p>
        </div>

        <Card className="border-red-200">
          <CardHeader className="space-y-3">
            <div className="flex items-start gap-3">
              <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-red-600" />
              <div>
                <CardTitle className="text-xl">{data.business_name}</CardTitle>
                <p className="mt-1 text-sm text-muted-foreground">
                  {formatBusinessType(data.business_type)}
                </p>
              </div>
            </div>
            <StatusBadge status="Rejected" />
          </CardHeader>
          <CardContent className="space-y-6">
            {data.rejection_reason && (
              <section className="rounded-lg border border-red-200 bg-red-50/80 p-4">
                <p className="text-xs font-medium uppercase tracking-wide text-red-800">
                  Rejection Reason
                </p>
                <p className="mt-2 text-sm leading-relaxed text-red-700">
                  {data.rejection_reason}
                </p>
              </section>
            )}

            <div className="grid gap-4 sm:grid-cols-2 text-sm">
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Owner
                </p>
                <p className="mt-1">{data.owner_name}</p>
              </div>
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Reviewed
                </p>
                <p className="mt-1">{formatDateTime(data.reviewed_at)}</p>
              </div>
            </div>

            <form onSubmit={handleSubmit} className="space-y-6">
              <div>
                <p className="mb-1 text-sm font-medium">Resubmit Documents</p>
                <p className="text-sm text-muted-foreground">
                  Replace any documents noted in the rejection reason. Files you
                  do not re-upload will keep your previous submission.
                </p>
              </div>

              {DOCUMENT_FIELDS.map((field) => (
                <DocumentUploadField
                  key={field.key}
                  id={field.key}
                  label={field.label}
                  existingFilename={existingByType[field.key]}
                  file={documents[field.key]}
                  error={documentErrors[field.key]}
                  onChange={(file) => updateDocument(field.key, file)}
                />
              ))}

              <Button
                type="submit"
                className="w-full"
                disabled={resubmit.isPending}
              >
                {resubmit.isPending ? "Resubmitting…" : "Resubmit Application"}
              </Button>
            </form>

            <Button asChild variant="outline" className="w-full">
              <Link to="/owner-login">Back to Owner Login</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
