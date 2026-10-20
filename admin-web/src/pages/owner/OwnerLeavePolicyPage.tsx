import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { LeaveAllowancesSection } from "@/components/owner/LeaveAllowancesSection";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  getLeavePolicy,
  updateLeavePolicy,
  type LeavePolicyItem,
} from "@/lib/api";

function PaidToggle({
  paid,
  onChange,
  label,
}: {
  paid: boolean;
  onChange: (next: boolean) => void;
  label: string;
}) {
  return (
    <div className="flex items-center gap-2.5">
      <span
        className={`text-xs font-semibold transition-colors ${
          paid ? "text-[#9CA3AF]" : "text-amber-700"
        }`}
      >
        Unpaid
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={paid}
        aria-label={`${label}: ${paid ? "Paid" : "Unpaid"} leave`}
        onClick={() => onChange(!paid)}
        className={`relative h-7 w-12 shrink-0 rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[color-mix(in_srgb,var(--owner-navy)_40%,transparent)] focus-visible:ring-offset-2 ${
          paid ? "bg-emerald-500" : "bg-slate-300"
        }`}
      >
        <span
          className={`absolute top-0.5 left-0.5 h-6 w-6 rounded-full bg-white shadow-sm transition-transform duration-200 ${
            paid ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </button>
      <span
        className={`text-xs font-semibold transition-colors ${
          paid ? "text-emerald-700" : "text-[#9CA3AF]"
        }`}
      >
        Paid
      </span>
    </div>
  );
}

export function OwnerLeavePolicyPage() {
  const qc = useQueryClient();
  const { data, isLoading, isError } = useQuery({
    queryKey: ["leave-policy"],
    queryFn: getLeavePolicy,
  });
  const [draft, setDraft] = useState<Record<string, boolean>>({});
  const [noticeDays, setNoticeDays] = useState("0");

  useEffect(() => {
    if (!data) return;
    const next: Record<string, boolean> = {};
    for (const item of data.items) {
      next[item.leave_type] = item.is_paid;
    }
    setDraft(next);
    setNoticeDays(String(data.minimum_advance_notice_days ?? 0));
  }, [data]);

  const noticeValue = Number(noticeDays);
  const noticeValid = Number.isInteger(noticeValue) && noticeValue >= 0 && noticeValue <= 365;
  const noticeDirty =
    data != null && noticeValid && noticeValue !== (data.minimum_advance_notice_days ?? 0);

  const save = useMutation({
    mutationFn: () =>
      updateLeavePolicy({
        treatments: Object.fromEntries(
          Object.entries(draft).filter(([leaveType]) => leaveType !== "unpaid"),
        ),
        minimum_advance_notice_days: noticeValue,
      }),
    onSuccess: () => {
      toast.success("Leave Policy saved");
      qc.invalidateQueries({ queryKey: ["leave-policy"] });
    },
    onError: () => toast.error("Could not save Leave Policy"),
  });

  const items: LeavePolicyItem[] = (data?.items ?? []).filter(
    (item) => item.leave_type !== "unpaid",
  );
  const dirty =
    noticeDirty ||
    (items.length > 0 &&
      items.some((item) => draft[item.leave_type] !== item.is_paid));

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Leave Policy"
        description="Set paid or unpaid leave, how far ahead leave must be requested, and the yearly allowance for every employee."
      />
      <OwnerPageContent>
        <OwnerPageBackLink to="/owner/settings/setup" label="Back to Business Setup" />

        <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <p className="text-sm text-[#6B7280]">
            Employees only pick the leave type. Payroll uses this policy. You
            can still override it when approving a request.
          </p>

          {isLoading ? (
            <p className="mt-6 text-sm text-[#6B7280]">Loading leave policy…</p>
          ) : isError ? (
            <p className="mt-6 text-sm text-red-600">
              Could not load leave policy.
            </p>
          ) : (
            <div className="mt-5 overflow-hidden rounded-xl border border-slate-200">
              {items.map((item, index) => {
                const paid = draft[item.leave_type] ?? item.is_paid;
                return (
                  <div
                    key={item.leave_type}
                    className={`flex items-center justify-between gap-4 bg-white px-4 py-3.5 ${
                      index > 0 ? "border-t border-slate-100" : ""
                    }`}
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold text-[#111827]">
                        {item.leave_type_label}
                      </p>
                      <p
                        className={`mt-0.5 text-xs font-medium ${
                          paid ? "text-emerald-600" : "text-amber-600"
                        }`}
                      >
                        {paid ? "Counts as paid leave" : "Counts as unpaid leave"}
                      </p>
                    </div>
                    <PaidToggle
                      paid={paid}
                      label={item.leave_type_label}
                      onChange={(next) =>
                        setDraft((prev) => ({
                          ...prev,
                          [item.leave_type]: next,
                        }))
                      }
                    />
                  </div>
                );
              })}
            </div>
          )}

          <div className="mt-5 rounded-xl border border-slate-200 px-4 py-3.5">
            <label
              className="text-sm font-semibold text-[#111827]"
              htmlFor="advance-notice-days"
            >
              Minimum advance notice
            </label>
            <p className="mt-0.5 text-xs text-[#6B7280]">
              Calendar days before the leave start date. 0 means no minimum.
              This applies to every leave type.
            </p>
            <div className="mt-3 flex items-center gap-2">
              <Input
                id="advance-notice-days"
                className="h-10 w-24 rounded-xl"
                inputMode="numeric"
                value={noticeDays}
                onChange={(event) =>
                  setNoticeDays(event.target.value.replace(/[^\d]/g, ""))
                }
              />
              <span className="text-sm text-[#6B7280]">days</span>
            </div>
          </div>

          <div className="mt-6 flex justify-end">
            <Button
              className="bg-[var(--owner-button)] hover:bg-[var(--owner-navy-soft)]"
              disabled={!dirty || !noticeValid || save.isPending || isLoading}
              onClick={() => save.mutate()}
            >
              {save.isPending ? "Saving…" : "Save Leave Policy"}
            </Button>
          </div>
        </div>

        <LeaveAllowancesSection />
      </OwnerPageContent>
    </OwnerPage>
  );
}
