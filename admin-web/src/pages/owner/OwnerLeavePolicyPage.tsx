import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
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
        className={`relative h-7 w-12 shrink-0 rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#1E3A5F]/40 focus-visible:ring-offset-2 ${
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

  useEffect(() => {
    if (!data) return;
    const next: Record<string, boolean> = {};
    for (const item of data.items) {
      next[item.leave_type] = item.is_paid;
    }
    setDraft(next);
  }, [data]);

  const save = useMutation({
    mutationFn: () => updateLeavePolicy({ treatments: draft }),
    onSuccess: () => {
      toast.success("Leave Policy saved");
      qc.invalidateQueries({ queryKey: ["leave-policy"] });
    },
    onError: () => toast.error("Could not save Leave Policy"),
  });

  const items: LeavePolicyItem[] = data?.items ?? [];
  const dirty =
    items.length > 0 &&
    items.some((item) => draft[item.leave_type] !== item.is_paid);

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Leave Policy"
        description="Toggle each leave type as Paid or Unpaid for payroll."
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

          <div className="mt-6 flex justify-end">
            <Button
              className="bg-[#1E3A5F] hover:bg-[#284B73]"
              disabled={!dirty || save.isPending || isLoading}
              onClick={() => save.mutate()}
            >
              {save.isPending ? "Saving…" : "Save Leave Policy"}
            </Button>
          </div>
        </div>
      </OwnerPageContent>
    </OwnerPage>
  );
}
