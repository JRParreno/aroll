import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  createConsentDocument,
  deleteConsentDocument,
  reorderConsentDocuments,
  updateConsentDocument,
  uploadConsentDocumentFile,
  type ConsentDocument,
  type ConsentDocumentWrite,
} from "@/lib/api";

const TYPES = [
  { value: "terms", label: "Terms" },
  { value: "privacy", label: "Privacy" },
  { value: "biometric", label: "Biometric" },
  { value: "custom", label: "Custom" },
] as const;

type EditorState = {
  id?: string;
  title: string;
  body_text: string;
  consent_type: string;
  is_active: boolean;
  is_required: boolean;
  file: File | null;
};

const EMPTY_EDITOR: EditorState = {
  title: "",
  body_text: "",
  consent_type: "custom",
  is_active: true,
  is_required: true,
  file: null,
};

export function ConsentDocumentManager({
  scope,
  documents,
  canEdit,
  onChanged,
  readOnlyHint,
  addButtonClassName,
}: {
  scope: "admin" | "owner";
  documents: ConsentDocument[];
  canEdit: boolean;
  onChanged: () => void;
  readOnlyHint?: string;
  addButtonClassName?: string;
}) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editor, setEditor] = useState<EditorState>(EMPTY_EDITOR);
  const ordered = useMemo(
    () => [...documents].sort((a, b) => a.position - b.position),
    [documents]
  );

  function openCreate() {
    setEditor(EMPTY_EDITOR);
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
      file: null,
    });
    setOpen(true);
  }

  async function save() {
    if (!editor.title.trim()) {
      toast.error("Title is required");
      return;
    }
    setSaving(true);
    try {
      const payload: ConsentDocumentWrite = {
        title: editor.title.trim(),
        body_text: editor.body_text,
        consent_type: editor.consent_type,
        is_active: editor.is_active,
        is_required: editor.is_required,
      };
      const saved = editor.id
        ? await updateConsentDocument(scope, editor.id, payload)
        : await createConsentDocument(scope, payload);
      if (editor.file) {
        await uploadConsentDocumentFile(scope, saved.id, editor.file);
      }
      toast.success(editor.id ? "Consent saved" : "Consent created");
      setOpen(false);
      onChanged();
    } catch {
      toast.error("Could not save consent document");
    } finally {
      setSaving(false);
    }
  }

  async function remove(doc: ConsentDocument) {
    if (!window.confirm(`Deactivate and delete “${doc.title}”?`)) return;
    try {
      await deleteConsentDocument(scope, doc.id);
      toast.success("Consent deleted");
      onChanged();
    } catch {
      toast.error("Could not delete consent document");
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
    } catch {
      toast.error("Could not reorder consents");
    }
  }

  return (
    <div className="space-y-4">
      {readOnlyHint ? (
        <p className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-600">
          {readOnlyHint}
        </p>
      ) : null}
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-slate-600">
          {ordered.length} document{ordered.length === 1 ? "" : "s"}
        </p>
        {canEdit ? (
          <Button type="button" className={addButtonClassName} onClick={openCreate}>
            Add consent
          </Button>
        ) : null}
      </div>
      <div className="overflow-hidden rounded-xl border border-slate-200">
        <table className="w-full text-left text-sm">
          <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th className="px-3 py-2">Title</th>
              <th className="px-3 py-2">Position</th>
              <th className="px-3 py-2">Active</th>
              <th className="px-3 py-2">Preview</th>
              {canEdit ? <th className="px-3 py-2">Actions</th> : null}
            </tr>
          </thead>
          <tbody>
            {ordered.length === 0 ? (
              <tr>
                <td className="px-3 py-4 text-slate-500" colSpan={canEdit ? 5 : 4}>
                  No consent documents yet.
                </td>
              </tr>
            ) : (
              ordered.map((doc) => (
                <tr key={doc.id} className="border-t border-slate-200">
                  <td className="px-3 py-3">
                    <p className="font-medium text-slate-900">{doc.title}</p>
                    <p className="text-xs text-slate-500">
                      {doc.consent_type} · {doc.version}
                      {doc.is_required ? " · required" : " · optional"}
                      {doc.has_file ? " · file attached" : ""}
                    </p>
                  </td>
                  <td className="px-3 py-3">{doc.position}</td>
                  <td className="px-3 py-3">{doc.is_active ? "Yes" : "No"}</td>
                  <td className="px-3 py-3">
                    <a
                      className="text-[#1E3A5F] underline"
                      href={doc.web_path}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {doc.web_path}
                    </a>
                  </td>
                  {canEdit ? (
                    <td className="px-3 py-3">
                      <div className="flex flex-wrap gap-2">
                        <Button type="button" variant="outline" onClick={() => openEdit(doc)}>
                          Edit
                        </Button>
                        <Button
                          type="button"
                          variant="outline"
                          onClick={() => move(doc, -1)}
                        >
                          Up
                        </Button>
                        <Button
                          type="button"
                          variant="outline"
                          onClick={() => move(doc, 1)}
                        >
                          Down
                        </Button>
                        <Button type="button" variant="outline" onClick={() => remove(doc)}>
                          Delete
                        </Button>
                      </div>
                    </td>
                  ) : null}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>{editor.id ? "Edit consent" : "New consent"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-2">
              <Label htmlFor="consent-title">Title</Label>
              <Input
                id="consent-title"
                value={editor.title}
                onChange={(event) =>
                  setEditor({ ...editor, title: event.target.value })
                }
              />
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
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
              <div className="flex items-end gap-4 pb-1">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={editor.is_active}
                    onChange={(event) =>
                      setEditor({ ...editor, is_active: event.target.checked })
                    }
                  />
                  Active
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={editor.is_required}
                    onChange={(event) =>
                      setEditor({ ...editor, is_required: event.target.checked })
                    }
                  />
                  Required
                </label>
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="consent-body">Body text</Label>
              <textarea
                id="consent-body"
                className="min-h-40 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                value={editor.body_text}
                onChange={(event) =>
                  setEditor({ ...editor, body_text: event.target.value })
                }
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="consent-file">File (PDF, JPG, or PNG)</Label>
              <Input
                id="consent-file"
                type="file"
                accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png"
                onChange={(event) =>
                  setEditor({
                    ...editor,
                    file: event.target.files?.[0] ?? null,
                  })
                }
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="button" onClick={() => void save()} disabled={saving}>
              {saving ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
