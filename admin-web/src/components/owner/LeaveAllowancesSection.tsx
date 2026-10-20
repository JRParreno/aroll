import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getLeaveAllowances, updateLeaveAllowances } from "@/lib/api";
import { cn } from "@/lib/utils";

export function LeaveAllowancesSection({ className }: { className?: string }) {
  const qc = useQueryClient();
  const [year, setYear] = useState(() => new Date().getFullYear());
  const [draft, setDraft] = useState<Record<string, { enabled: boolean; days: string }>>({});
  const { data, isLoading, isError } = useQuery({
    queryKey: ["leave-allowances", year],
    queryFn: () => getLeaveAllowances(year),
  });

  useEffect(() => {
    if (!data) return;
    const next: Record<string, { enabled: boolean; days: string }> = {};
    for (const item of data.items) {
      next[item.leave_type] = {
        enabled: item.enabled,
        days: item.allowance_days === null ? "" : String(item.allowance_days),
      };
    }
    setDraft(next);
  }, [data]);

  const allowanceItems = (data?.items ?? []).filter(
    (item) => item.leave_type !== "unpaid",
  );
  const invalid = allowanceItems.some((item) => {
    const row = draft[item.leave_type];
    if (!row?.enabled) return false;
    if (row.days.trim() === "") return true;
    const value = Number(row.days);
    return !Number.isInteger(value) || value < 0 || value > 366;
  });

  const save = useMutation({
    mutationFn: () =>
      updateLeaveAllowances({
        year,
        items: allowanceItems.map((item) => {
          const row = draft[item.leave_type] ?? { enabled: false, days: "" };
          return {
            leave_type: item.leave_type,
            enabled: row.enabled,
            allowance_days: row.enabled ? Number(row.days) : null,
          };
        }),
      }),
    onSuccess: () => {
      toast.success("Leave allowances saved");
      void qc.invalidateQueries({ queryKey: ["leave-allowances", year] });
      void qc.invalidateQueries({ queryKey: ["employee-leave-balances"] });
    },
    onError: () => toast.error("Could not save leave allowances"),
  });

  return (
    <div
      className={cn(
        "mt-6 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm",
        className,
      )}
    >
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold text-[#111827]">Leave Allowances</h2>
          <p className="mt-1 text-sm text-[#6B7280]">
            These days apply to every employee for {year}. Available off means
            employees cannot request that leave type.
          </p>
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            className="h-8 w-8 rounded-lg border border-slate-200 text-sm"
            onClick={() => setYear((current) => current - 1)}
            aria-label="Previous allowance year"
          >
            ‹
          </button>
          <span className="min-w-12 text-center text-sm font-semibold">{year}</span>
          <button
            type="button"
            className="h-8 w-8 rounded-lg border border-slate-200 text-sm"
            onClick={() => setYear((current) => current + 1)}
            aria-label="Next allowance year"
          >
            ›
          </button>
        </div>
      </div>
      {isLoading ? (
        <p className="mt-4 text-sm text-[#6B7280]">Loading allowances…</p>
      ) : isError ? (
        <p className="mt-4 text-sm text-red-600">Could not load leave allowances.</p>
      ) : (
        <div className="mt-4 space-y-3">
          {allowanceItems.map((item) => {
            const row = draft[item.leave_type] ?? { enabled: false, days: "" };
            return (
              <div
                key={item.leave_type}
                className="rounded-xl border border-slate-100 bg-[#FAFBFC] px-3 py-3"
              >
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm font-semibold text-[#111827]">
                    {item.leave_type_label}
                  </p>
                  <label className="flex items-center gap-2 text-xs font-medium text-[#374151]">
                    Available
                    <input
                      type="checkbox"
                      checked={row.enabled}
                      aria-label={`${item.leave_type_label} available`}
                      onChange={(event) =>
                        setDraft((current) => ({
                          ...current,
                          [item.leave_type]: {
                            enabled: event.target.checked,
                            days: event.target.checked
                              ? current[item.leave_type]?.days ?? ""
                              : "",
                          },
                        }))
                      }
                    />
                  </label>
                </div>
                <label className="mt-2 block text-xs font-medium text-[#6B7280]">
                  Allowance Days
                  <Input
                    className="mt-1 h-10 w-28 rounded-xl bg-white"
                    inputMode="numeric"
                    disabled={!row.enabled}
                    placeholder={row.enabled ? "Set allowance" : "—"}
                    aria-label={`${item.leave_type_label} allowance days`}
                    value={row.enabled ? row.days : ""}
                    onChange={(event) =>
                      setDraft((current) => ({
                        ...current,
                        [item.leave_type]: {
                          enabled: true,
                          days: event.target.value.replace(/[^\d]/g, ""),
                        },
                      }))
                    }
                  />
                </label>
              </div>
            );
          })}
        </div>
      )}
      <div className="mt-4 flex justify-end">
        <Button
          className="bg-[var(--owner-button)] hover:bg-[var(--owner-navy-soft)]"
          disabled={isLoading || invalid || save.isPending}
          onClick={() => save.mutate()}
        >
          {save.isPending ? "Saving…" : "Save Allowances"}
        </Button>
      </div>
    </div>
  );
}
