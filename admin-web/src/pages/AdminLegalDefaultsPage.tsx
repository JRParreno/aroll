import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Scale } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  getPlatformLegalSettings,
  updatePlatformLegalSettings,
  type PlatformLegalSettings,
} from "@/lib/api";

type LegalForm = {
  terms_content: string;
  privacy_content: string;
  biometric_consent_content: string;
  terms_version: string;
  privacy_version: string;
  biometric_consent_version: string;
  terms_published: boolean;
  privacy_published: boolean;
  biometric_published: boolean;
};

const EMPTY_FORM: LegalForm = {
  terms_content: "",
  privacy_content: "",
  biometric_consent_content: "",
  terms_version: "",
  privacy_version: "",
  biometric_consent_version: "",
  terms_published: true,
  privacy_published: true,
  biometric_published: true,
};

function formFromSettings(data: PlatformLegalSettings): LegalForm {
  return {
    terms_content: data.terms.content ?? "",
    privacy_content: data.privacy.content ?? "",
    biometric_consent_content: data.biometric.content ?? "",
    terms_version: data.terms.version ?? "",
    privacy_version: data.privacy.version ?? "",
    biometric_consent_version: data.biometric.version ?? "",
    terms_published: data.terms.published,
    privacy_published: data.privacy.published,
    biometric_published: data.biometric.published,
  };
}

export function AdminLegalDefaultsPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState<LegalForm>(EMPTY_FORM);
  const { data, isLoading, isError } = useQuery({
    queryKey: ["admin-legal-defaults"],
    queryFn: getPlatformLegalSettings,
  });

  useEffect(() => {
    if (!data) return;
    setForm(formFromSettings(data));
  }, [data]);

  const save = useMutation({
    mutationFn: () =>
      updatePlatformLegalSettings({
        terms_content: form.terms_content,
        privacy_content: form.privacy_content,
        biometric_consent_content: form.biometric_consent_content,
        terms_version: form.terms_version,
        privacy_version: form.privacy_version,
        biometric_consent_version: form.biometric_consent_version,
        terms_published: form.terms_published,
        privacy_published: form.privacy_published,
        biometric_published: form.biometric_published,
      }),
    onSuccess: (saved) => {
      setForm(formFromSettings(saved));
      qc.invalidateQueries({ queryKey: ["admin-legal-defaults"] });
      toast.success("Legal defaults saved");
    },
    onError: () => toast.error("Failed to save legal defaults"),
  });

  const fields = [
    {
      contentKey: "terms_content",
      versionKey: "terms_version",
      publishedKey: "terms_published",
      label: "Terms and Conditions",
    },
    {
      contentKey: "privacy_content",
      versionKey: "privacy_version",
      publishedKey: "privacy_published",
      label: "Privacy Policy",
    },
    {
      contentKey: "biometric_consent_content",
      versionKey: "biometric_consent_version",
      publishedKey: "biometric_published",
      label: "Biometric Consent",
    },
  ] as const;

  return (
    <div className="min-h-full bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-[#6B7280]">Platform legal</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-[#1F2937] sm:text-3xl">
            Legal Defaults
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
            These published documents are the default Terms, Privacy Policy, and
            Biometric Consent for every business unless an owner enables a
            custom workplace override. Changing a version requires employees at
            default-mode businesses to re-consent. Custom workplaces are not
            affected.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
        {isError ? (
          <p className="text-sm text-red-700">
            Legal defaults could not be loaded.
          </p>
        ) : (
          <Card className="overflow-hidden rounded-2xl border-slate-200 bg-white shadow-sm">
            <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
              <CardTitle className="flex items-center gap-2 text-base font-semibold text-[#1F2937]">
                <Scale className="h-4 w-4" />
                Platform default documents
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6 p-5 sm:p-6">
              {isLoading ? (
                <p className="text-sm text-[#6B7280]">Loading defaults…</p>
              ) : (
                fields.map((field) => (
                  <div key={field.contentKey} className="space-y-2">
                    <div className="flex flex-wrap items-end gap-3">
                      <div className="min-w-[16rem] flex-1 space-y-2">
                        <Label htmlFor={field.contentKey}>{field.label}</Label>
                        <textarea
                          id={field.contentKey}
                          className="min-h-40 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                          value={form[field.contentKey]}
                          onChange={(event) =>
                            setForm({
                              ...form,
                              [field.contentKey]: event.target.value,
                            })
                          }
                        />
                      </div>
                      <div className="w-52 space-y-2">
                        <Label htmlFor={field.versionKey}>Version</Label>
                        <Input
                          id={field.versionKey}
                          value={form[field.versionKey]}
                          onChange={(event) =>
                            setForm({
                              ...form,
                              [field.versionKey]: event.target.value,
                            })
                          }
                          placeholder="e.g. terms-2026-09-09"
                        />
                        <label className="flex items-center gap-2 text-sm text-[#374151]">
                          <input
                            type="checkbox"
                            checked={form[field.publishedKey]}
                            onChange={(event) =>
                              setForm({
                                ...form,
                                [field.publishedKey]: event.target.checked,
                              })
                            }
                          />
                          Published
                        </label>
                      </div>
                    </div>
                  </div>
                ))
              )}
              <Button
                type="button"
                onClick={() => save.mutate()}
                disabled={isLoading || save.isPending}
              >
                Save legal defaults
              </Button>
            </CardContent>
          </Card>
        )}
      </main>
    </div>
  );
}
