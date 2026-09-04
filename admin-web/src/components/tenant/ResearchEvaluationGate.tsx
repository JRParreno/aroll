import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  RESEARCH_ACK_STORAGE_KEY,
  RESEARCH_ATTESTATION,
  RESEARCH_VOLUNTARY,
  useTenantMode,
} from "@/lib/tenantMode";

export function ResearchEvaluationGate() {
  const { isDemo } = useTenantMode();
  const [open, setOpen] = useState(false);
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    if (!isDemo) {
      setOpen(false);
      return;
    }
    try {
      setOpen(sessionStorage.getItem(RESEARCH_ACK_STORAGE_KEY) !== "1");
    } catch {
      setOpen(true);
    }
  }, [isDemo]);

  if (!isDemo || !open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 px-4"
      data-testid="research-evaluation-gate"
    >
      <div className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-6 shadow-xl">
        <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#6B7280]">
          Research evaluation
        </p>
        <h2 className="mt-1 text-lg font-semibold text-[#111827]">
          18+ voluntary participation
        </h2>
        <p className="mt-3 text-sm leading-6 text-[#4B5563]">{RESEARCH_VOLUNTARY}</p>
        <label className="mt-4 flex cursor-pointer items-start gap-3 rounded-xl border border-slate-200 bg-slate-50 p-3 text-sm text-[#1F2937]">
          <input
            checked={checked}
            className="mt-1 h-4 w-4"
            onChange={(event) => setChecked(event.target.checked)}
            type="checkbox"
          />
          <span>{RESEARCH_ATTESTATION}</span>
        </label>
        <div className="mt-5 flex justify-end">
          <Button
            disabled={!checked}
            onClick={() => {
              try {
                sessionStorage.setItem(RESEARCH_ACK_STORAGE_KEY, "1");
              } catch {
                // Acknowledgement is UI-only; demo mode still comes from the session.
              }
              setOpen(false);
            }}
          >
            Continue
          </Button>
        </div>
      </div>
    </div>
  );
}
