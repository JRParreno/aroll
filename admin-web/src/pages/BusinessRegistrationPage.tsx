import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  getRegistrationByEmail,
  submitRegistration,
  submitRegistrationApplication,
  uploadRegistrationDocument,
} from "@/lib/api";

const STEPS = ["Business Information", "Document Upload"];

const ACCEPTED_FILE_TYPES = ".pdf,.jpg,.jpeg,.png";

type BusinessTypeOption = "restaurant" | "cafe" | "other" | "";

type DocumentKey =
  | "business_permit"
  | "valid_id"
  | "dti_sec"
  | "bir_cor";

const DOCUMENT_FIELDS: {
  key: DocumentKey;
  label: string;
}[] = [
  { key: "business_permit", label: "Business Permit" },
  { key: "valid_id", label: "Valid ID of Owner" },
  { key: "dti_sec", label: "DTI or SEC Registration" },
  { key: "bir_cor", label: "BIR Certificate of Registration" },
];

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

function RegistrationStepIndicator({ step }: { step: number }) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-2">
      {STEPS.map((label, index) => (
        <div
          key={label}
          className={`whitespace-nowrap rounded-full px-3 py-1 text-xs ${
            index === step
              ? "bg-[#1e3a5f] text-white"
              : index < step
                ? "bg-[#3b9ae8]/20 text-[#1e3a5f]"
                : "bg-muted text-muted-foreground"
          }`}
        >
          Step {index + 1}: {label}
        </div>
      ))}
    </div>
  );
}

type DocumentUploadFieldProps = {
  id: string;
  label: string;
  file: File | null;
  error?: string;
  onChange: (file: File | null) => void;
};

function DocumentUploadField({
  id,
  label,
  file,
  error,
  onChange,
}: DocumentUploadFieldProps) {
  const [typeError, setTypeError] = useState<string | null>(null);

  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
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
      </div>
      {file ? (
        <p className="text-sm text-foreground">Uploaded: {file.name}</p>
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

export function BusinessRegistrationPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [registrationId, setRegistrationId] = useState<string | null>(null);
  const [checkingEmail, setCheckingEmail] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [step1Errors, setStep1Errors] = useState<Record<string, string>>({});
  const [documentErrors, setDocumentErrors] = useState<
    Partial<Record<DocumentKey, string>>
  >({});

  const [form, setForm] = useState({
    business_name: "",
    owner_name: "",
    owner_email: "",
    owner_phone: "",
    proposed_address: "",
    business_type: "" as BusinessTypeOption,
    business_type_other: "",
  });

  const [documents, setDocuments] = useState<DocumentFiles>({
    business_permit: null,
    valid_id: null,
    dti_sec: null,
    bir_cor: null,
  });

  function validateStep1() {
    const errors: Record<string, string> = {};

    if (!form.business_name.trim()) errors.business_name = "Business name is required";
    if (!form.owner_name.trim()) errors.owner_name = "Owner name is required";
    if (!form.owner_email.trim()) errors.owner_email = "Owner email is required";
    if (!form.owner_phone.trim()) errors.owner_phone = "Phone number is required";
    if (!form.proposed_address.trim()) {
      errors.proposed_address = "Business address is required";
    }
    if (!form.business_type) errors.business_type = "Business type is required";
    if (form.business_type === "other" && !form.business_type_other.trim()) {
      errors.business_type_other = "Please specify your business type";
    }

    setStep1Errors(errors);
    return Object.keys(errors).length === 0;
  }

  function validateDocuments() {
    const errors: Partial<Record<DocumentKey, string>> = {};

    for (const field of DOCUMENT_FIELDS) {
      if (!documents[field.key]) {
        errors[field.key] = `${field.label} is required`;
      }
    }

    setDocumentErrors(errors);
    return Object.keys(errors).length === 0;
  }

  function resolveBusinessType() {
    return form.business_type === "other"
      ? form.business_type_other.trim()
      : form.business_type;
  }

  async function handleNext() {
    if (!validateStep1()) return;

    setCheckingEmail(true);
    try {
      try {
        const existing = await getRegistrationByEmail(form.owner_email);
        if (existing.application_status === "pending") {
          navigate(
            `/pending-verification?email=${encodeURIComponent(form.owner_email.trim())}`
          );
          return;
        }
        if (existing.application_status === "rejected") {
          navigate(
            `/rejected-application?email=${encodeURIComponent(form.owner_email.trim())}`
          );
          return;
        }
        if (existing.application_status === "draft") {
          setRegistrationId(existing.id);
          setStep(1);
          return;
        }
      } catch {
        // No existing registration — create a new draft.
      }

      const created = await submitRegistration({
        business_name: form.business_name.trim(),
        owner_name: form.owner_name.trim(),
        owner_email: form.owner_email.trim(),
        owner_phone: form.owner_phone.trim(),
        proposed_address: form.proposed_address.trim(),
        business_type: resolveBusinessType(),
      });
      setRegistrationId(created.id);
      setStep(1);
    } catch {
      toast.error("Unable to continue registration. This email may already have an active application.");
    } finally {
      setCheckingEmail(false);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!validateDocuments() || !registrationId) {
      if (!registrationId) {
        toast.error("Registration session expired. Please go back to step 1.");
      }
      return;
    }

    setSubmitting(true);
    try {
      for (const field of DOCUMENT_FIELDS) {
        const file = documents[field.key];
        if (file) {
          await uploadRegistrationDocument(registrationId, field.key, file);
        }
      }
      await submitRegistrationApplication(registrationId);
      navigate(
        `/pending-verification?email=${encodeURIComponent(form.owner_email.trim())}`
      );
    } catch {
      toast.error("Failed to submit application. Please try again.");
    } finally {
      setSubmitting(false);
    }
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

  return (
    <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
      <div className="mx-auto flex max-w-xl flex-col gap-6">
        <div>
          <h1 className="text-2xl font-semibold">Business Registration</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Register your business with Aroll+. Complete both steps to submit
            your application.
          </p>
        </div>

        <RegistrationStepIndicator step={step} />

        <Card>
          <CardHeader>
            <CardTitle>{STEPS[step]}</CardTitle>
            <p className="text-sm text-muted-foreground">
              Step {step + 1} of {STEPS.length}
            </p>
          </CardHeader>

          <CardContent>
            {step === 0 && (
              <form
                className="space-y-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  void handleNext();
                }}
              >
                <div className="space-y-2">
                  <Label htmlFor="business_name">Business Name</Label>
                  <Input
                    id="business_name"
                    value={form.business_name}
                    onChange={(e) =>
                      setForm({ ...form, business_name: e.target.value })
                    }
                  />
                  {step1Errors.business_name && (
                    <p className="text-sm text-red-600">{step1Errors.business_name}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="owner_name">Owner Name</Label>
                  <Input
                    id="owner_name"
                    value={form.owner_name}
                    onChange={(e) =>
                      setForm({ ...form, owner_name: e.target.value })
                    }
                  />
                  {step1Errors.owner_name && (
                    <p className="text-sm text-red-600">{step1Errors.owner_name}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="owner_email">Owner Email</Label>
                  <Input
                    id="owner_email"
                    type="email"
                    value={form.owner_email}
                    onChange={(e) =>
                      setForm({ ...form, owner_email: e.target.value })
                    }
                  />
                  {step1Errors.owner_email && (
                    <p className="text-sm text-red-600">{step1Errors.owner_email}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="owner_phone">Phone Number</Label>
                  <Input
                    id="owner_phone"
                    value={form.owner_phone}
                    onChange={(e) =>
                      setForm({ ...form, owner_phone: e.target.value })
                    }
                  />
                  {step1Errors.owner_phone && (
                    <p className="text-sm text-red-600">{step1Errors.owner_phone}</p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="proposed_address">Business Address</Label>
                  <Input
                    id="proposed_address"
                    value={form.proposed_address}
                    onChange={(e) =>
                      setForm({ ...form, proposed_address: e.target.value })
                    }
                  />
                  {step1Errors.proposed_address && (
                    <p className="text-sm text-red-600">
                      {step1Errors.proposed_address}
                    </p>
                  )}
                </div>

                <div className="space-y-2">
                  <Label htmlFor="business_type">Business Type</Label>
                  <select
                    id="business_type"
                    className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                    value={form.business_type}
                    onChange={(e) =>
                      setForm({
                        ...form,
                        business_type: e.target.value as BusinessTypeOption,
                        business_type_other:
                          e.target.value === "other"
                            ? form.business_type_other
                            : "",
                      })
                    }
                  >
                    <option value="">Select business type</option>
                    <option value="restaurant">Restaurant</option>
                    <option value="cafe">Cafe</option>
                    <option value="other">Other</option>
                  </select>
                  {step1Errors.business_type && (
                    <p className="text-sm text-red-600">{step1Errors.business_type}</p>
                  )}
                </div>

                {form.business_type === "other" && (
                  <div className="space-y-2">
                    <Label htmlFor="business_type_other">Specify Business Type</Label>
                    <Input
                      id="business_type_other"
                      value={form.business_type_other}
                      onChange={(e) =>
                        setForm({ ...form, business_type_other: e.target.value })
                      }
                      placeholder="e.g. Retail, Salon, Gym"
                    />
                    {step1Errors.business_type_other && (
                      <p className="text-sm text-red-600">
                        {step1Errors.business_type_other}
                      </p>
                    )}
                  </div>
                )}

                <Button type="submit" className="w-full" disabled={checkingEmail}>
                  {checkingEmail ? "Checking…" : "Next"}
                </Button>
              </form>
            )}

            {step === 1 && (
              <form
                onSubmit={(e) => {
                  void handleSubmit(e);
                }}
                className="space-y-6"
              >
                <p className="text-sm text-muted-foreground">
                  Upload the required documents for verification. All files are
                  required before submission.
                </p>

                {DOCUMENT_FIELDS.map((field) => (
                  <DocumentUploadField
                    key={field.key}
                    id={field.key}
                    label={field.label}
                    file={documents[field.key]}
                    error={documentErrors[field.key]}
                    onChange={(file) => updateDocument(field.key, file)}
                  />
                ))}

                <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-between">
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => setStep(0)}
                  >
                    Back
                  </Button>
                  <Button
                    type="submit"
                    className="sm:min-w-[180px]"
                    disabled={submitting}
                  >
                    {submitting ? "Submitting…" : "Submit Application"}
                  </Button>
                </div>
              </form>
            )}
          </CardContent>
        </Card>

        <p className="text-center text-sm text-muted-foreground">
          Already registered?{" "}
          <Link to="/owner-login" className="underline underline-offset-2">
            Sign in here
          </Link>
        </p>
      </div>
    </div>
  );
}
