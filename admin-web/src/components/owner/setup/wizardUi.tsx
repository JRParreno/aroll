import { Check } from "lucide-react";
import { Children, type SelectHTMLAttributes } from "react";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

export const wizardInputClass =
  "h-11 w-full min-w-0 rounded-xl border-slate-200 bg-white";

export const wizardSelectClass =
  "flex h-11 w-full min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-[#1F2937] outline-none transition focus-visible:ring-2 focus-visible:ring-[#1E3A5F]/25";

export const wizardPrimaryBtnClass =
  "h-10 rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]";

export const wizardOutlineBtnClass = "h-10 rounded-xl border-slate-200";

export function WizardField({
  label,
  hint,
  className,
  children,
}: {
  label: React.ReactNode;
  hint?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={cn("min-w-0 space-y-2", className)}>
      <Label>{label}</Label>
      {children}
      {hint ? (
        <p className="text-xs leading-5 text-[#6B7280]">{hint}</p>
      ) : null}
    </div>
  );
}

export function WizardSelect({
  className,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select className={cn(wizardSelectClass, className)} {...props} />;
}

export function WizardSection({
  title,
  description,
  children,
  className,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("owner-card-muted space-y-4 p-4 sm:p-5", className)}>
      <div className="min-w-0">
        <p className="owner-section-title">{title}</p>
        {description ? (
          <p className="owner-section-subtitle mt-1">{description}</p>
        ) : null}
      </div>
      {children}
    </section>
  );
}

export function WizardNotice({
  children,
  tone = "info",
  className,
}: {
  children: React.ReactNode;
  tone?: "info" | "warning" | "error";
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-xl px-4 py-3 text-sm leading-6",
        tone === "info" && "bg-[#F3F6FA] text-[#6B7280]",
        tone === "warning" && "border border-amber-200 bg-amber-50 text-amber-800",
        tone === "error" && "border border-red-200 bg-red-50 text-red-700",
        className
      )}
    >
      {children}
    </div>
  );
}

export function WizardToggle({
  checked,
  onChange,
  label,
  disabled,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative h-6 w-11 shrink-0 rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#1E3A5F]/40 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
        checked ? "bg-[#1E3A5F]" : "bg-slate-300"
      )}
    >
      <span
        className={cn(
          "absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform duration-200",
          checked ? "translate-x-5" : "translate-x-0"
        )}
      />
    </button>
  );
}

export function WizardSettingRow({
  title,
  description,
  checked,
  onChange,
  disabled,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-start justify-between gap-4 rounded-xl border border-slate-200/80 bg-white px-4 py-3">
      <div className="min-w-0">
        <p className="text-sm font-medium text-[#1F2937]">{title}</p>
        {description ? (
          <p className="mt-0.5 text-xs leading-5 text-[#6B7280]">{description}</p>
        ) : null}
      </div>
      <div className="flex shrink-0 items-center gap-2 pt-0.5">
        <span
          className={cn(
            "text-[11px] font-medium uppercase tracking-wide",
            checked ? "text-[#1E3A5F]" : "text-[#9CA3AF]"
          )}
        >
          {checked ? "On" : "Off"}
        </span>
        <WizardToggle
          checked={checked}
          onChange={onChange}
          label={typeof title === "string" ? title : "Toggle setting"}
          disabled={disabled}
        />
      </div>
    </div>
  );
}

export function WizardRecordList({
  children,
  empty,
}: {
  children: React.ReactNode;
  empty?: React.ReactNode;
}) {
  const count = Children.count(children);

  if (count === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-slate-200 bg-[#FAFBFC] px-4 py-6 text-center text-sm text-[#6B7280]">
        {empty ?? "Nothing added yet"}
      </div>
    );
  }

  return (
    <ul className="divide-y divide-slate-100 overflow-hidden rounded-2xl border border-slate-200/90 bg-white text-sm">
      {children}
    </ul>
  );
}

export function WizardStepTrack({
  current,
  labels,
  complete,
  onSelect,
}: {
  current: number;
  labels: readonly string[];
  complete: boolean[];
  onSelect?: (index: number) => void;
}) {
  return (
    <ol className="mt-3 hidden min-w-0 sm:flex sm:items-center">
      {labels.map((label, index) => {
        const done = complete[index] === true;
        const active = index === current;
        return (
          <li key={label} className="flex min-w-0 flex-1 items-center">
            {index > 0 ? (
              <div
                className={cn(
                  "mx-1 h-px min-w-2 flex-1",
                  index <= current || done ? "bg-[#1E3A5F]/35" : "bg-slate-200"
                )}
              />
            ) : null}
            <button
              type="button"
              title={label}
              onClick={() => onSelect?.(index)}
              className={cn(
                "flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[11px] font-medium transition",
                active && "bg-[#1E3A5F] text-white shadow-sm",
                !active && done && "bg-emerald-100 text-emerald-700",
                !active && !done && "bg-[#EEF3F8] text-[#6B7280] hover:bg-[#E4EBF3]"
              )}
            >
              {done && !active ? <Check className="h-3.5 w-3.5" strokeWidth={2.5} /> : index + 1}
            </button>
          </li>
        );
      })}
    </ol>
  );
}
