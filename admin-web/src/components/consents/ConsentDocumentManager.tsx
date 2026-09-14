import { useMemo, useRef, useState } from "react";
import {
  ChevronDown,
  ChevronUp,
  Eye,
  FileText,
  Pencil,
  Plus,
  Trash2,
  Upload,
} from "lucide-react";
import { toast } from "sonner";
import { StatusBadge } from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  createConsentDocument,
  deleteConsentDocument,
  reorderConsentDocuments,
  updateConsentDocument,
  uploadConsentDocumentFile,
  type ConsentDocument,
  type ConsentDocumentWrite,
} from "@/lib/api";
import { cn } from "@/lib/utils";

const TYPES = [
  { value: "terms", label: "Terms" },
  { value: "privacy", label: "Privacy" },
  { value: "biometric", label: "Biometric" },
  { value: "custom", label: "Custom" },
] as const;

const ALLOWED_EXTENSIONS = [".pdf", ".jpg", ".jpeg", ".png"];
const ALLOWED_TYPES = new Set(["application/pdf", "image/jpeg", "image/png"]);
const MAX_FILE_BYTES = 10 * 1024 * 1024;

type EditorState = {
  id?: string;
  title: string;
  body_text: string;
  consent_type: string;
  is_active: boolean;
  is_required: boolean;
  position: string;
  file: File | null;
  fileError: string | null;
  hasFile: boolean;
  existingFilename: string | null;
  webPath: string | null;
  apiUrl: string | null;
};

const EMPTY_EDITOR: EditorState = {
  title: "",
  body_text: "",
  consent_type: "custom",
  is_active: true,
  is_required: true,
  position: "",
  file: null,
  fileError: null,
  hasFile: false,
  existingFilename: null,
  webPath: null,
  apiUrl: null,
};

function typeLabel(value: string) {
  return TYPES.find((item) => item.value === value)?.label ?? value;
}

function sourceLabel(doc: ConsentDocument) {
  if (doc.has_file) return "Uploaded file";
  if (doc.body_text?.trim()) return "Text";
  return "No content";
}

function apiErrorMessage(error: unknown, fallback: string) {
  if (typeof error === "object" && error !== null && "response" in error) {
    const detail = (error as { response?: { data?: { detail?: unknown } } })
      .response?.data?.detail;
    if (typeof detail === "string" && detail.trim()) return detail;
  }
  return fallback;
}

function validateConsentFile(file: File): string | null {
  const name = file.name.toLowerCase();
  const allowedExt = ALLOWED_EXTENSIONS.some((ext) => name.endsWith(ext));
  if (!allowedExt && !ALLOWED_TYPES.has(file.type)) {
    return "File must be PDF, JPG, or PNG.";
  }
  if (file.size > MAX_FILE_BYTES) {
    return "File exceeds the 10MB limit.";
  }
  return null;
}

export function ConsentDocumentManager({
  scope,
  documents,
  canEdit,
  onChanged,
  readOnlyHint,
}: {
  scope: "admin" | "owner";
  documents: ConsentDocument[];
  canEdit: boolean;
  onChanged: () => void;
  readOnlyHint?: string;
}) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editor, setEditor] = useState<EditorState>(EMPTY_EDITOR);
  const [pendingDelete, setPendingDelete] = useState<ConsentDocument | null>(
    null
  );
  const [deleting, setDeleting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const ordered = useMemo(
    () => [...documents].sort((a, b) => a.position - b.position),
    [documents]
  );

  function openCreate() {
    setEditor({
      ...EMPTY_EDITOR,
      position: String(ordered.length + 1),
    });
    setOpen(true);
  }

  function openEdit(doc: ConsentDocument) {
    setEditor({
      id: doc.id,
      title: doc.title,
      body_text: doc.body_text ?? "",
      consent_type: doc.consent_type,
      is_active: doc.is_active,
      is_required: doc.is_required,
      position: String(doc.position),
      file: null,
      fileError: null,
      hasFile: doc.has_file,
      existingFilename: doc.original_filename,
      webPath: doc.web_path,
      apiUrl: doc.url,
    });
    setOpen(true);
  }

  function applyFile(file: File | null) {
    if (!file) {
      setEditor((current) => ({
        ...current,
        file: null,
        fileError: null,
      }));
      return;
    }
    const error = validateConsentFile(file);
    setEditor((current) => ({
      ...current,
      file: error ? null : file,
      fileError: error,
    }));
  }

  async function save() {
    if (!editor.title.trim()) {
      toast.error("Title is required");
      return;
    }
    if (editor.fileError) {
      toast.error(editor.fileError);
      return;
    }
    setSaving(true);
    try {
      const parsedPosition = Number.parseInt(editor.position, 10);
      const payload: ConsentDocumentWrite = {
        title: editor.title.trim(),
        body_text: editor.body_text,
        consent_type: editor.consent_type,
        is_active: editor.is_active,
        is_required: editor.is_required,
      };
      if (Number.isInteger(parsedPosition) && parsedPosition > 0) {
        payload.position = parsedPosition;
      }
      const saved = editor.id
        ? await updateConsentDocument(scope, editor.id, payload)
        : await createConsentDocument(scope, payload);
      if (editor.file) {
        await uploadConsentDocumentFile(scope, saved.id, editor.file);
      }
      toast.success(editor.id ? "Consent saved" : "Consent created");
      setOpen(false);
      onChanged();
    } catch (error) {
      toast.error(apiErrorMessage(error, "Could not save consent document"));
    } finally {
      setSaving(false);
    }
  }

  async function confirmDelete() {
    if (!pendingDelete) return;
    setDeleting(true);
    try {
      await deleteConsentDocument(scope, pendingDelete.id);
      toast.success("Consent deleted");
      setPendingDelete(null);
      onChanged();
    } catch (error) {
      toast.error(apiErrorMessage(error, "Could not delete consent document"));
    } finally {
      setDeleting(false);
    }
  }

  async function move(doc: ConsentDocument, direction: -1 | 1) {
    const ids = ordered.map((item) => item.id);
    const index = ids.indexOf(doc.id);
    const next = index + direction;
    if (index < 0 || next < 0 || next >= ids.length) return;
    const swapped = [...ids];
    const [current] = swapped.splice(index, 1);
    swapped.splice(next, 0, current);
    try {
      await reorderConsentDocuments(scope, swapped);
      onChanged();
    } catch (error) {
      toast.error(apiErrorMessage(error, "Could not reorder consents"));
    }
  }

  const publicUrl = editor.webPath
    ? `${window.location.origin}${editor.webPath}`
    : null;

  return (
    <div className="space-y-4">
      {readOnlyHint ? (
        <p className="rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 py-3 text-sm text-[#6B7280]">
          {readOnlyHint}
        </p>
      ) : null}

      {canEdit && ordered.length > 0 ? (
        <div className="flex justify-end">
          <Button type="button" onClick={openCreate}>
            <Plus className="mr-1.5 h-4 w-4" />
            Add consent
          </Button>
        </div>
      ) : null}

      {ordered.length === 0 ? (
        <div className="px-6 py-14 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#EAF2FB] text-[#1E3A5F]">
            <FileText className="h-6 w-6" />
          </div>
          <p className="mt-4 font-medium text-[#1F2937]">
            No consent documents yet
          </p>
          <p className="mt-1 text-sm text-[#6B7280]">
            Add an ordered document so employees can review and accept it in the
            app.
          </p>
          {canEdit ? (
            <Button type="button" className="mt-5" onClick={openCreate}>
              <Plus className="mr-1.5 h-4 w-4" />
              Add consent
            </Button>
          ) : null}
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-slate-200">
          <div className="hidden gap-4 border-b border-slate-200 bg-white px-5 py-3 text-xs font-medium uppercase tracking-wide text-[#6B7280] lg:grid lg:grid-cols-[minmax(0,1.4fr)_4.5rem_minmax(0,0.95fr)_minmax(0,0.9fr)_auto]">
            <span>Title</span>
            <span>Order</span>
            <span>Status</span>
            <span>Source</span>
            <span className="text-right">Actions</span>
          </div>
          <div className="divide-y divide-slate-100">
            {ordered.map((doc, index) => (
              <article
                key={doc.id}
                className="grid gap-4 p-5 lg:grid-cols-[minmax(0,1.4fr)_4.5rem_minmax(0,0.95fr)_minmax(0,0.9fr)_auto] lg:items-center"
              >
                <div className="min-w-0">
                  <p className="font-medium text-[#1F2937]">{doc.title}</p>
                  <p className="mt-1 text-sm text-[#6B7280]">
                    {typeLabel(doc.consent_type)}
                    {doc.version ? ` · ${doc.version}` : ""}
                  </p>
                </div>
                <div>
                  <span className="inline-flex h-8 min-w-8 items-center justify-center rounded-lg bg-[#EAF2FB] px-2 text-sm font-semibold text-[#1E3A5F]">
                    {doc.position}
                  </span>
                </div>
                <div className="flex flex-wrap gap-2">
                  <StatusBadge status={doc.is_active ? "active" : "inactive"} />
                  <span
                    className={cn(
                      "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold",
                      doc.is_required
                        ? "border-[#1E3A5F]/15 bg-[#EAF2FB] text-[#1E3A5F]"
                        : "border-slate-200 bg-slate-50 text-[#6B7280]"
                    )}
                  >
                    {doc.is_required ? "Required" : "Optional"}
                  </span>
                </div>
                <div>
                  <p className="text-sm font-medium text-[#1F2937]">
                    {sourceLabel(doc)}
                  </p>
                  <p className="mt-0.5 truncate text-xs text-[#6B7280]">
                    {doc.has_file
                      ? doc.original_filename || "Attached file"
                      : doc.body_text?.trim()
                        ? "Written in the editor"
                        : "Add text or a file to publish"}
                  </p>
                </div>
                <div className="flex flex-wrap items-center justify-start gap-2 lg:justify-end">
                  <Button type="button" variant="outline" size="sm" asChild>
                    <a href={doc.web_path} target="_blank" rel="noreferrer">
                      <Eye className="mr-1.5 h-3.5 w-3.5" />
                      Preview
                    </a>
                  </Button>
                  {canEdit ? (
                    <>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => openEdit(doc)}
                      >
                        <Pencil className="mr-1.5 h-3.5 w-3.5" />
                        Edit
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        aria-label="Move up"
                        disabled={index === 0}
                        onClick={() => void move(doc, -1)}
                      >
                        <ChevronUp className="h-4 w-4" />
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        aria-label="Move down"
                        disabled={index === ordered.length - 1}
                        onClick={() => void move(doc, 1)}
                      >
                        <ChevronDown className="h-4 w-4" />
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => setPendingDelete(doc)}
                      >
                        <Trash2 className="mr-1.5 h-3.5 w-3.5" />
                        Delete
                      </Button>
                    </>
                  ) : null}
                </div>
              </article>
            ))}
          </div>
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>
              {editor.id ? "Edit consent" : "New consent"}
            </DialogTitle>
            <DialogDescription>
              Employees review this document in the app WebView. Required
              documents must be accepted before continuing.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-6">
            <section className="space-y-4">
              <div>
                <h3 className="text-sm font-semibold text-[#1F2937]">
                  Basic information
                </h3>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Title, order, and whether this document is required and active.
                </p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="consent-title">Title</Label>
                <Input
                  id="consent-title"
                  value={editor.title}
                  placeholder="Workplace terms"
                  onChange={(event) =>
                    setEditor({ ...editor, title: event.target.value })
                  }
                />
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="consent-position">Position</Label>
                  <Input
                    id="consent-position"
                    type="number"
                    min={1}
                    value={editor.position}
                    onChange={(event) =>
                      setEditor({ ...editor, position: event.target.value })
                    }
                  />
                  <p className="text-xs text-[#6B7280]">
                    Lower numbers appear first. You can also reorder from the
                    list.
                  </p>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="consent-type">Type</Label>
                  <select
                    id="consent-type"
                    className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                    value={editor.consent_type}
                    onChange={(event) =>
                      setEditor({ ...editor, consent_type: event.target.value })
                    }
                  >
                    {TYPES.map((item) => (
                      <option key={item.value} value={item.value}>
                        {item.label}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="flex items-start gap-3 rounded-xl border border-slate-200 px-3 py-3 text-sm">
                  <input
                    type="checkbox"
                    className="mt-1"
                    checked={editor.is_required}
                    onChange={(event) =>
                      setEditor({
                        ...editor,
                        is_required: event.target.checked,
                      })
                    }
                  />
                  <span>
                    <span className="font-medium text-[#1F2937]">Required</span>
                    <span className="mt-1 block text-[#6B7280]">
                      Employees must accept this document.
                    </span>
                  </span>
                </label>
                <label className="flex items-start gap-3 rounded-xl border border-slate-200 px-3 py-3 text-sm">
                  <input
                    type="checkbox"
                    className="mt-1"
                    checked={editor.is_active}
                    onChange={(event) =>
                      setEditor({ ...editor, is_active: event.target.checked })
                    }
                  />
                  <span>
                    <span className="font-medium text-[#1F2937]">Active</span>
                    <span className="mt-1 block text-[#6B7280]">
                      Inactive documents are hidden from employees.
                    </span>
                  </span>
                </label>
              </div>
            </section>

            <section className="space-y-4 border-t border-slate-200 pt-5">
              <div>
                <h3 className="text-sm font-semibold text-[#1F2937]">
                  Consent content
                </h3>
                <p className="mt-1 text-sm text-[#6B7280]">
                  Write the document text, or upload a PDF, JPG, or PNG. An
                  uploaded file can be used as the consent document employees
                  review.
                </p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="consent-body">Body text</Label>
                <textarea
                  id="consent-body"
                  className="min-h-40 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                  value={editor.body_text}
                  placeholder="Paste or write the consent document…"
                  onChange={(event) =>
                    setEditor({ ...editor, body_text: event.target.value })
                  }
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="consent-file">File upload</Label>
                <div
                  className={cn(
                    "rounded-xl border border-dashed px-4 py-5 text-center",
                    editor.fileError
                      ? "border-red-300 bg-red-50"
                      : "border-slate-300 bg-[#FAFBFC]"
                  )}
                  onDragOver={(event) => event.preventDefault()}
                  onDrop={(event) => {
                    event.preventDefault();
                    applyFile(event.dataTransfer.files?.[0] ?? null);
                  }}
                >
                  <Upload className="mx-auto h-5 w-5 text-[#1E3A5F]" />
                  <p className="mt-2 text-sm font-medium text-[#1F2937]">
                    Drop a PDF, JPG, or PNG here
                  </p>
                  <p className="mt-1 text-xs text-[#6B7280]">
                    Supported types: PDF, JPG, PNG. Maximum 10MB.
                  </p>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="mt-3"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    Choose file
                  </Button>
                  <input
                    ref={fileInputRef}
                    id="consent-file"
                    type="file"
                    className="sr-only"
                    accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png"
                    onChange={(event) =>
                      applyFile(event.target.files?.[0] ?? null)
                    }
                  />
                </div>
                {editor.file ? (
                  <p className="text-sm text-[#1F2937]">
                    Selected file: {editor.file.name}
                  </p>
                ) : editor.hasFile ? (
                  <p className="text-sm text-[#6B7280]">
                    Current file: {editor.existingFilename || "Attached file"}.
                    Choose a new file to replace it.
                  </p>
                ) : (
                  <p className="text-sm text-[#6B7280]">No file selected.</p>
                )}
                {editor.fileError ? (
                  <p className="text-sm text-red-700">{editor.fileError}</p>
                ) : null}
              </div>
            </section>

            <section className="space-y-3 border-t border-slate-200 pt-5">
              <div>
                <h3 className="text-sm font-semibold text-[#1F2937]">
                  Generated public document
                </h3>
                <p className="mt-1 text-sm text-[#6B7280]">
                  This public URL is what employees open in the app WebView. No
                  sign-in is required to view it.
                </p>
              </div>
              {publicUrl ? (
                <div className="space-y-3 rounded-xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <div className="space-y-2">
                    <Label htmlFor="consent-public-url">Public URL</Label>
                    <Input id="consent-public-url" readOnly value={publicUrl} />
                  </div>
                  {editor.apiUrl ? (
                    <p className="break-all text-xs text-[#6B7280]">
                      WebView page: {editor.apiUrl}
                    </p>
                  ) : null}
                  <Button type="button" variant="outline" size="sm" asChild>
                    <a href={editor.webPath ?? "#"} target="_blank" rel="noreferrer">
                      <Eye className="mr-1.5 h-3.5 w-3.5" />
                      Preview
                    </a>
                  </Button>
                </div>
              ) : (
                <p className="rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 py-3 text-sm text-[#6B7280]">
                  Save this consent to generate a public webpage URL.
                </p>
              )}
            </section>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="button" onClick={() => void save()} disabled={saving}>
              {saving
                ? editor.file
                  ? "Uploading…"
                  : "Saving…"
                : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={pendingDelete !== null}
        onOpenChange={(nextOpen) => {
          if (!nextOpen && !deleting) setPendingDelete(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete consent</DialogTitle>
            <DialogDescription>
              Delete “{pendingDelete?.title}”? This removes the document from
              the catalog. Existing acceptance records are not edited here.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              disabled={deleting}
              onClick={() => setPendingDelete(null)}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              disabled={deleting}
              onClick={() => void confirmDelete()}
            >
              {deleting ? "Deleting…" : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
