import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Library, MoreHorizontal } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  applyScheduleReuse,
  createScheduleTemplate,
  deleteScheduleTemplate,
  getScheduleReuseSuggestions,
  previewScheduleReuse,
  renameScheduleTemplate,
  type ScheduleConflictMode,
  type ScheduleReusePreview,
  type ScheduleReuseSource,
} from "@/lib/api";
import { formatShiftTime } from "@/components/owner/schedule/scheduleUtils";

type Props = {
  weekStartKey: string;
  weekLabel: string;
  assignmentCount: number;
};

function apiError(error: unknown, fallback: string) {
  if (
    typeof error === "object" &&
    error !== null &&
    "response" in error &&
    typeof error.response === "object" &&
    error.response !== null &&
    "data" in error.response &&
    typeof error.response.data === "object" &&
    error.response.data !== null &&
    "detail" in error.response.data
  ) {
    return String(error.response.data.detail);
  }
  return fallback;
}

/** Minimal Schedule Library trigger — icon opens a floating panel on the page. */
export function ScheduleReusePanel({
  weekStartKey,
  weekLabel,
  assignmentCount,
}: Props) {
  const qc = useQueryClient();
  const rootRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [saveOpen, setSaveOpen] = useState(false);
  const [preview, setPreview] = useState<ScheduleReusePreview | null>(null);
  const [pendingSource, setPendingSource] = useState<{
    source: ScheduleReuseSource;
    template_id?: string;
  } | null>(null);
  const [conflictMode, setConflictMode] =
    useState<ScheduleConflictMode>("merge");
  const [templateName, setTemplateName] = useState("");
  const [menuTemplateId, setMenuTemplateId] = useState<string | null>(null);
  const [templateToDelete, setTemplateToDelete] = useState<{
    id: string;
    name: string;
  } | null>(null);

  const { data: suggestions } = useQuery({
    queryKey: ["schedule-reuse-suggestions", weekStartKey],
    queryFn: () => getScheduleReuseSuggestions(weekStartKey),
  });

  useEffect(() => {
    setOpen(false);
  }, [weekStartKey]);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) {
        setOpen(false);
        setMenuTemplateId(null);
      }
    }
    document.addEventListener("mousedown", onPointerDown);
    return () => document.removeEventListener("mousedown", onPointerDown);
  }, [open]);

  const previewMutation = useMutation({
    mutationFn: previewScheduleReuse,
    onSuccess: (data) => {
      setPreview(data);
      setPreviewOpen(true);
      setOpen(false);
      setConflictMode("merge");
    },
    onError: (error) => toast.error(apiError(error, "Unable to preview schedule")),
  });

  const applyMutation = useMutation({
    mutationFn: applyScheduleReuse,
    onSuccess: (result) => {
      toast.success(
        `Applied schedule: ${result.created} added` +
          (result.removed > 0 ? `, ${result.removed} replaced` : "") +
          (result.skipped > 0 ? `, ${result.skipped} skipped` : "")
      );
      setPreviewOpen(false);
      setPreview(null);
      setPendingSource(null);
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
      qc.invalidateQueries({ queryKey: ["schedule-reuse-suggestions"] });
      qc.invalidateQueries({ queryKey: ["owner-performance"] });
    },
    onError: (error) => toast.error(apiError(error, "Unable to apply schedule")),
  });

  const saveTemplateMutation = useMutation({
    mutationFn: () =>
      createScheduleTemplate({ name: templateName.trim(), week_start: weekStartKey }),
    onSuccess: () => {
      toast.success("Template saved");
      setTemplateName("");
      setSaveOpen(false);
      qc.invalidateQueries({ queryKey: ["schedule-reuse-suggestions"] });
    },
    onError: (error) => toast.error(apiError(error, "Unable to save template")),
  });

  const renameMutation = useMutation({
    mutationFn: ({ id, name }: { id: string; name: string }) =>
      renameScheduleTemplate(id, name),
    onSuccess: () => {
      toast.success("Template renamed");
      setMenuTemplateId(null);
      qc.invalidateQueries({ queryKey: ["schedule-reuse-suggestions"] });
    },
    onError: (error) => toast.error(apiError(error, "Unable to rename template")),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteScheduleTemplate,
    onSuccess: () => {
      toast.success("Template deleted");
      setMenuTemplateId(null);
      setTemplateToDelete(null);
      qc.invalidateQueries({ queryKey: ["schedule-reuse-suggestions"] });
    },
    onError: (error) => toast.error(apiError(error, "Unable to delete template")),
  });

  function startPreview(payload: {
    source: ScheduleReuseSource;
    template_id?: string;
  }) {
    setPendingSource(payload);
    previewMutation.mutate({
      ...payload,
      target_week_start: weekStartKey,
    });
  }

  const conflictSummary = useMemo(() => preview?.conflicts ?? null, [preview]);
  const suggestPrevious =
    !!suggestions?.suggest_previous && assignmentCount === 0;

  return (
    <>
      <div className="relative" ref={rootRef}>
        <button
          type="button"
          title="Schedule Library"
          aria-label="Schedule Library"
          aria-expanded={open}
          onClick={() => setOpen((value) => !value)}
          className={`inline-flex h-10 w-10 items-center justify-center rounded-xl border transition ${
            open
              ? "border-[#1E3A5F] bg-[#1E3A5F] text-white"
              : "border-slate-200 bg-white text-[#1E3A5F] hover:bg-[#F3F6F9]"
          }`}
        >
          <Library className="h-4 w-4" />
        </button>

        {open && (
          <div className="absolute right-0 top-[calc(100%+0.5rem)] z-40 w-[min(20rem,calc(100vw-2rem))] overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xl">
            <div className="flex items-start gap-3 border-b border-slate-100 px-4 py-3">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-[#E7EEF5] text-[#1E466E]">
                <Library className="h-4 w-4" />
              </div>
              <div>
                <p className="text-sm font-semibold text-[#1F2937]">
                  Schedule Library
                </p>
                <p className="text-xs text-[#6B7280]">
                  Reuse a past week or template for {weekLabel}
                </p>
              </div>
            </div>

            {suggestPrevious && (
              <div className="mx-3 mt-3 rounded-xl bg-[#E7EEF5] px-3 py-2 text-xs text-[#1E3A5F]">
                Tip: this week is empty. Copy last week to get started.
              </div>
            )}

            <div className="py-1">
              <LibraryRow
                title="Copy previous week"
                subtitle={
                  suggestions?.previous_week_start
                    ? `${suggestions.previous_week_assignment_count} assignments`
                    : "Nothing to copy"
                }
                disabled={!suggestions?.previous_week_start || previewMutation.isPending}
                onClick={() => startPreview({ source: "previous_week" })}
              />
              <LibraryRow
                title="Use last schedule"
                subtitle={
                  suggestions?.last_schedule_week_start
                    ? `Week of ${suggestions.last_schedule_week_start}`
                    : "No previous schedule"
                }
                disabled={
                  !suggestions?.last_schedule_week_start || previewMutation.isPending
                }
                onClick={() => startPreview({ source: "last_schedule" })}
              />
              <LibraryRow
                title="Save this week"
                subtitle={
                  assignmentCount > 0
                    ? "Save as a reusable template"
                    : "Assign someone first"
                }
                disabled={assignmentCount === 0}
                onClick={() => {
                  setOpen(false);
                  setTemplateName("");
                  setSaveOpen(true);
                }}
              />
            </div>

            <div className="border-t border-slate-100 px-4 pb-3 pt-2">
              <p className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[#6B7280]">
                Saved templates
              </p>
              {(suggestions?.templates ?? []).length === 0 ? (
                <p className="py-2 text-sm text-[#6B7280]">No templates yet.</p>
              ) : (
                <div className="max-h-48 space-y-1 overflow-y-auto">
                  {suggestions?.templates.map((template) => (
                    <div
                      key={template.id}
                      className="flex items-center gap-1 rounded-xl px-1 py-1.5 hover:bg-[#F9FAFB]"
                    >
                      <button
                        type="button"
                        className="min-w-0 flex-1 rounded-lg px-2 py-1 text-left"
                        onClick={() =>
                          startPreview({
                            source: "template",
                            template_id: template.id,
                          })
                        }
                      >
                        <p className="truncate text-sm font-medium text-[#1F2937]">
                          {template.name}
                        </p>
                        <p className="text-xs text-[#6B7280]">
                          {template.entry_count} assignments ·{" "}
                          {template.employee_count} employees
                        </p>
                      </button>
                      <div className="relative">
                        <button
                          type="button"
                          className="rounded-lg p-1.5 text-[#6B7280] hover:bg-slate-100"
                          onClick={() =>
                            setMenuTemplateId((id) =>
                              id === template.id ? null : template.id
                            )
                          }
                        >
                          <MoreHorizontal className="h-4 w-4" />
                        </button>
                        {menuTemplateId === template.id && (
                          <div className="absolute right-0 top-8 z-50 w-32 rounded-xl border border-slate-200 bg-white py-1 shadow-lg">
                            <button
                              type="button"
                              className="block w-full px-3 py-2 text-left text-sm hover:bg-slate-50"
                              onClick={() => {
                                const name = window.prompt(
                                  "Rename template",
                                  template.name
                                );
                                if (name?.trim()) {
                                  renameMutation.mutate({
                                    id: template.id,
                                    name: name.trim(),
                                  });
                                }
                              }}
                            >
                              Rename
                            </button>
                            <button
                              type="button"
                              className="block w-full px-3 py-2 text-left text-sm text-red-600 hover:bg-slate-50"
                              onClick={() => {
                                setMenuTemplateId(null);
                                setOpen(false);
                                setTemplateToDelete({
                                  id: template.id,
                                  name: template.name,
                                });
                              }}
                            >
                              Delete
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      <Dialog
        open={Boolean(templateToDelete)}
        onOpenChange={(open) => {
          if (!open && !deleteMutation.isPending) setTemplateToDelete(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete template</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-[#6B7280]">
            {`Are you sure you want to delete "${templateToDelete?.name ?? "this template"}"? This cannot be undone.`}
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setTemplateToDelete(null)}
              disabled={deleteMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              disabled={!templateToDelete || deleteMutation.isPending}
              onClick={() => {
                if (templateToDelete) {
                  deleteMutation.mutate(templateToDelete.id);
                }
              }}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={saveOpen} onOpenChange={setSaveOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Save as template</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-[#6B7280]">
            Save this week’s assignments so you can reuse them later.
          </p>
          <Input
            placeholder="e.g. Regular Week"
            value={templateName}
            onChange={(e) => setTemplateName(e.target.value)}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setSaveOpen(false)}>
              Cancel
            </Button>
            <Button
              className="bg-[#1E3A5F] hover:bg-[#284B73]"
              disabled={!templateName.trim() || saveTemplateMutation.isPending}
              onClick={() => saveTemplateMutation.mutate()}
            >
              Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={previewOpen && !!preview}
        onOpenChange={(next) => {
          if (!next) {
            setPreviewOpen(false);
            setPreview(null);
            setPendingSource(null);
          }
        }}
      >
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Preview before applying</DialogTitle>
          </DialogHeader>
          {preview && (
            <div className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-3">
                <div className="rounded-xl bg-[#F9FAFB] px-3 py-2">
                  <p className="text-xs text-[#6B7280]">Source</p>
                  <p className="text-sm font-medium text-[#1F2937]">
                    {preview.source_label}
                  </p>
                </div>
                <div className="rounded-xl bg-[#F9FAFB] px-3 py-2">
                  <p className="text-xs text-[#6B7280]">Employees</p>
                  <p className="text-sm font-medium text-[#1F2937]">
                    {preview.employee_count}
                  </p>
                </div>
                <div className="rounded-xl bg-[#F9FAFB] px-3 py-2">
                  <p className="text-xs text-[#6B7280]">Working days</p>
                  <p className="text-sm font-medium text-[#1F2937]">
                    {preview.working_day_count}
                  </p>
                </div>
              </div>
              <p className="text-sm text-[#6B7280]">
                Date range: {preview.target_week_start} to {preview.target_week_end}.
              </p>

              {conflictSummary &&
                (conflictSummary.existing_assignment_count > 0 ||
                  conflictSummary.conflict_count > 0 ||
                  conflictSummary.duplicate_count > 0) && (
                  <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-3 text-sm text-amber-950">
                    <p className="font-medium">This week already has schedules</p>
                    <p className="mt-1 text-amber-900/90">
                      Existing: {conflictSummary.existing_assignment_count} ·
                      Conflicts: {conflictSummary.conflict_count} · Can add:{" "}
                      {conflictSummary.creatable_count}
                    </p>
                    <div className="mt-3 flex flex-wrap gap-2">
                      <Button
                        size="sm"
                        variant={conflictMode === "merge" ? "default" : "outline"}
                        className={
                          conflictMode === "merge"
                            ? "bg-[#1E3A5F] hover:bg-[#284B73]"
                            : ""
                        }
                        onClick={() => setConflictMode("merge")}
                      >
                        Keep & add
                      </Button>
                      <Button
                        size="sm"
                        variant={conflictMode === "replace" ? "default" : "outline"}
                        className={
                          conflictMode === "replace"
                            ? "bg-[#1E3A5F] hover:bg-[#284B73]"
                            : ""
                        }
                        onClick={() => setConflictMode("replace")}
                      >
                        Replace week
                      </Button>
                    </div>
                  </div>
                )}

              <div className="max-h-64 overflow-y-auto rounded-xl border border-slate-200">
                <table className="w-full text-sm">
                  <thead className="sticky top-0 bg-[#F9FAFB] text-left text-[#6B7280]">
                    <tr>
                      <th className="px-3 py-2 font-medium">Employee</th>
                      <th className="px-3 py-2 font-medium">Shift</th>
                      <th className="px-3 py-2 font-medium">Date</th>
                      <th className="px-3 py-2 font-medium">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {preview.items.map((item, index) => (
                      <tr
                        key={`${item.employee_id}-${item.shift_id}-${item.work_date}-${index}`}
                        className="border-t border-slate-100"
                      >
                        <td className="px-3 py-2 text-[#1F2937]">
                          {item.employee_name}
                        </td>
                        <td className="px-3 py-2 text-[#6B7280]">
                          {item.shift_name} (
                          {formatShiftTime(item.shift_start_time)}-
                          {formatShiftTime(item.shift_end_time)})
                        </td>
                        <td className="px-3 py-2 text-[#6B7280]">
                          {item.work_date}
                        </td>
                        <td className="px-3 py-2">
                          <span
                            className={
                              item.status === "new"
                                ? "text-emerald-700"
                                : "text-amber-700"
                            }
                          >
                            {item.status === "new"
                              ? "Will add"
                              : item.conflict_reason ?? item.status}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setPreviewOpen(false);
                setPreview(null);
                setPendingSource(null);
              }}
            >
              Cancel
            </Button>
            <Button
              className="bg-[#1E3A5F] hover:bg-[#284B73]"
              disabled={!pendingSource || applyMutation.isPending}
              onClick={() => {
                if (!pendingSource) return;
                applyMutation.mutate({
                  ...pendingSource,
                  target_week_start: weekStartKey,
                  conflict_mode: conflictMode,
                });
              }}
            >
              Apply
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function LibraryRow({
  title,
  subtitle,
  disabled,
  onClick,
}: {
  title: string;
  subtitle: string;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left hover:bg-[#F9FAFB] disabled:cursor-not-allowed disabled:opacity-40"
    >
      <div className="min-w-0">
        <p className="text-sm font-medium text-[#1F2937]">{title}</p>
        <p className="truncate text-xs text-[#6B7280]">{subtitle}</p>
      </div>
      <span className="text-[#9CA3AF]">›</span>
    </button>
  );
}
