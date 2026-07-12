import { useState } from "react";
import { ArrowLeft, FileCheck2, UploadCloud } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { SystemBrandPanel } from "@/components/branding/SystemBranding";
import { Button } from "@/components/ui/button";
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
    <div className="flex gap-3 overflow-x-auto pb-2">
      {STEPS.map((label, index) => (
        <div
          key={label}
          className={`whitespace-nowrap rounded-full px-4 py-2 text-xs font-medium ${
            index === step
              ? "bg-[#1E3A5F] text-white shadow-sm"
              : index < step
                ? "bg-[#DBEAFE] text-[#1E3A5F]"
                : "bg-white text-[#6B7280]"
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
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="mb-3 flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#EAF2FB] text-[#1E3A5F]">
          <UploadCloud className="h-5 w-5" />
        </div>
        <div>
          <Label htmlFor={id} className="text-sm font-medium text-[#1F2937]">
            {label}
          </Label>
          <p className="text-xs text-[#6B7280]">PDF, JPG, JPEG, or PNG</p>
        </div>
      </div>
      <Input
        id={id}
        type="file"
        accept={ACCEPTED_FILE_TYPES}
        className="cursor-pointer border-slate-200 bg-[#FAFBFC]"
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
        <p className="mt-2 text-sm text-[#1F2937]">Uploaded: {file.name}</p>
      ) : (
        <p className="mt-2 text-xs text-[#6B7280]">
          Accepted formats: PDF, JPG, JPEG, PNG
        </p>
      )}
      {typeError && <p className="mt-2 text-sm text-red-600">{typeError}</p>}
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
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
        // No existing registration - create a new draft.
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
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[minmax(300px,38vw)_1fr]">
      <SystemBrandPanel />

      <main className="flex min-h-screen items-center justify-center px-5 py-8 sm:px-8 lg:px-12">
        <div className="w-full max-w-4xl">
          <div className="mb-8 flex items-start gap-5">
            <Button
              asChild
              variant="ghost"
              size="icon"
              className="mt-1 h-11 w-11 rounded-full text-[#111827] hover:bg-white"
            >
              <Link to="/owner-login" aria-label="Back to login">
                <ArrowLeft className="h-6 w-6" />
              </Link>
            </Button>
            <div className="min-w-0">
              <h1 className="text-3xl font-semibold tracking-tight text-[#111827] sm:text-4xl">
                Let's create your account!
              </h1>
              <p className="mt-3 max-w-2xl text-sm leading-6 text-[#6B7280]">
                Register your business with Aroll+. Complete both steps to
                submit your application.
              </p>
            </div>
          </div>

          <RegistrationStepIndicator step={step} />

          <section className="mt-5 rounded-3xl border border-white/70 bg-white/70 p-5 shadow-sm backdrop-blur sm:p-7">
            <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold text-[#111827]">
                  {STEPS[step]}
                </h2>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Step {step + 1} of {STEPS.length}
                </p>
              </div>
              <div className="flex items-center gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-xs font-medium text-[#1E3A5F]">
                <FileCheck2 className="h-4 w-4" />
                Business verification
              </div>
            </div>

            {step === 0 && (
              <form
                className="space-y-5"
                onSubmit={(e) => {
                  e.preventDefault();
                  void handleNext();
                }}
              >
                <div className="grid gap-5 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label htmlFor="business_name">Business Name</Label>
                    <Input
                      id="business_name"
                      className="h-11 rounded-lg border-0 bg-white shadow-sm"
                      value={form.business_name}
                      onChange={(e) =>
                        setForm({ ...form, business_name: e.target.value })
                      }
                    />
                    {step1Errors.business_name && (
                      <p className="text-sm text-red-600">
                        {step1Errors.business_name}
                      </p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="owner_name">Owner Name</Label>
                    <Input
                      id="owner_name"
                      className="h-11 rounded-lg border-0 bg-white shadow-sm"
                      value={form.owner_name}
                      onChange={(e) =>
                        setForm({ ...form, owner_name: e.target.value })
                      }
                    />
                    {step1Errors.owner_name && (
                      <p className="text-sm text-red-600">
                        {step1Errors.owner_name}
                      </p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="owner_email">Owner Email</Label>
                    <Input
                      id="owner_email"
                      type="email"
                      className="h-11 rounded-lg border-0 bg-white shadow-sm"
                      value={form.owner_email}
                      onChange={(e) =>
                        setForm({ ...form, owner_email: e.target.value })
                      }
                    />
                    {step1Errors.owner_email && (
                      <p className="text-sm text-red-600">
                        {step1Errors.owner_email}
                      </p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="owner_phone">Phone Number</Label>
                    <Input
                      id="owner_phone"
                      className="h-11 rounded-lg border-0 bg-white shadow-sm"
                      value={form.owner_phone}
                      onChange={(e) =>
                        setForm({ ...form, owner_phone: e.target.value })
                      }
                    />
                    {step1Errors.owner_phone && (
                      <p className="text-sm text-red-600">
                        {step1Errors.owner_phone}
                      </p>
                    )}
                  </div>

                  <div className="space-y-2 md:col-span-2">
                    <Label htmlFor="proposed_address">Business Address</Label>
                    <Input
                      id="proposed_address"
                      className="h-11 rounded-lg border-0 bg-white shadow-sm"
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
                      className="flex h-11 w-full rounded-lg border-0 bg-white px-3 py-2 text-sm shadow-sm outline-none focus:ring-2 focus:ring-[#1E3A5F]/30"
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
                      <p className="text-sm text-red-600">
                        {step1Errors.business_type}
                      </p>
                    )}
                  </div>

                  {form.business_type === "other" && (
                    <div className="space-y-2">
                      <Label htmlFor="business_type_other">
                        Specify Business Type
                      </Label>
                      <Input
                        id="business_type_other"
                        className="h-11 rounded-lg border-0 bg-white shadow-sm"
                        value={form.business_type_other}
                        onChange={(e) =>
                          setForm({
                            ...form,
                            business_type_other: e.target.value,
                          })
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
                </div>

                <div className="flex justify-end pt-3">
                  <Button
                    type="submit"
                    className="h-12 min-w-48 rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                    disabled={checkingEmail}
                  >
                    {checkingEmail ? "Checking..." : "Next"}
                  </Button>
                </div>
              </form>
            )}

            {step === 1 && (
              <form
                onSubmit={(e) => {
                  void handleSubmit(e);
                }}
                className="space-y-6"
              >
                <p className="text-sm leading-6 text-[#6B7280]">
                  Upload the required documents for verification. All files are
                  required before submission.
                </p>

                <div className="grid gap-4 md:grid-cols-2">
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
                </div>

                <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:justify-between">
                  <Button
                    type="button"
                    variant="outline"
                    className="h-11 rounded-xl border-slate-200 bg-white"
                    onClick={() => setStep(0)}
                  >
                    Back
                  </Button>
                  <Button
                    type="submit"
                    className="h-11 min-w-48 rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                    disabled={submitting}
                  >
                    {submitting ? "Submitting..." : "Submit Application"}
                  </Button>
                </div>
              </form>
            )}
          </section>

          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <Button
              asChild
              variant="outline"
              className="h-11 rounded-xl border-slate-200 bg-white"
            >
              <Link to="/track-registration">Track Your Registration</Link>
            </Button>

            <p className="flex items-center justify-center text-center text-sm text-[#6B7280]">
              Already registered?{" "}
              <Link
                to="/owner-login"
                className="ml-1 font-medium text-[#1E3A5F] underline underline-offset-2"
              >
                Sign in here
              </Link>
            </p>
          </div>
        </div>
      </main>
    </div>
  );
}
