import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { cn } from "@/lib/utils";

type PageHeaderProps = {
  backTo: string;
  backLabel: string;
  title: string;
  description?: string;
  badge?: React.ReactNode;
  actions?: React.ReactNode;
};

/** In-content heading used when a page does not use AdminPageHeader. */
export function PageHeader({
  backTo,
  backLabel,
  title,
  description,
  badge,
  actions,
}: PageHeaderProps) {
  return (
    <div className="space-y-4">
      <Link
        to={backTo}
        className="inline-flex items-center gap-2 rounded-lg px-1 py-0.5 text-sm font-medium text-[#6B7280] transition-colors hover:bg-white hover:text-[#1E3A5F]"
      >
        <ArrowLeft className="h-4 w-4" />
        {backLabel}
      </Link>

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0 space-y-1.5">
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="owner-page-title">{title}</h1>
            {badge}
          </div>
          {description && (
            <p className="owner-section-subtitle max-w-2xl">{description}</p>
          )}
        </div>
        {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
      </div>
    </div>
  );
}

type DetailFieldProps = {
  label: string;
  value: React.ReactNode;
  icon?: React.ReactNode;
  className?: string;
};

export function DetailField({ label, value, icon, className }: DetailFieldProps) {
  return (
    <div className={cn("space-y-1.5", className)}>
      <p className="owner-label flex items-center gap-2 uppercase text-[#6B7280]">
        {icon}
        {label}
      </p>
      <div className="text-[0.9375rem] font-medium leading-relaxed text-[#1F2937]">
        {value ?? "—"}
      </div>
    </div>
  );
}

type DetailSectionProps = {
  title: string;
  description?: string;
  icon?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
};

export function DetailSection({
  title,
  description,
  icon,
  children,
  className,
}: DetailSectionProps) {
  return (
    <section className={cn("owner-card p-5 sm:p-6", className)}>
      <div className="mb-5 flex items-start gap-3">
        {icon && (
          <div className="owner-icon-well h-9 w-9 shrink-0">{icon}</div>
        )}
        <div>
          <h2 className="owner-section-title">{title}</h2>
          {description && (
            <p className="owner-section-subtitle mt-1">{description}</p>
          )}
        </div>
      </div>
      <div className="grid gap-5 sm:grid-cols-2">{children}</div>
    </section>
  );
}

type StatusBadgeProps = {
  status: string;
};

const statusStyles: Record<string, string> = {
  pending: "bg-amber-50 text-amber-700 border-amber-200",
  "pending verification": "bg-amber-50 text-amber-700 border-amber-200",
  approved: "bg-emerald-50 text-emerald-700 border-emerald-200",
  rejected: "bg-red-50 text-red-700 border-red-200",
  active: "bg-emerald-50 text-emerald-700 border-emerald-200",
  inactive: "bg-slate-100 text-slate-600 border-slate-200",
  suspended: "bg-orange-50 text-orange-700 border-orange-200",
};

export function StatusBadge({ status }: StatusBadgeProps) {
  const normalized = status.toLowerCase();
  const style =
    statusStyles[normalized] ?? "bg-muted text-muted-foreground border-border";

  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize",
        style
      )}
    >
      {status.replace(/_/g, " ")}
    </span>
  );
}

export function formatDateTime(value?: string | null) {
  if (!value) return "—";
  return new Date(value).toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function EmptyState({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div className="rounded-2xl border border-dashed border-slate-200 bg-[#FAFBFC] px-6 py-10 text-center">
      <p className="owner-section-title">{title}</p>
      <p className="owner-section-subtitle mt-1">{description}</p>
    </div>
  );
}
