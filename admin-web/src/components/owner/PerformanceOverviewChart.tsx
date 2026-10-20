import type { OwnerPerformanceSummary } from "@/lib/api";
import { cn } from "@/lib/utils";

export type PerformanceBarKey =
  | "on_time_clock_ins"
  | "late_clock_ins"
  | "undertime_shifts"
  | "overtime_shifts"
  | "absent_shifts";

export type PerformanceBarCategory =
  | "on_time"
  | "late"
  | "undertime"
  | "overtime"
  | "absent";

type PerformanceOverviewChartProps = {
  summary: OwnerPerformanceSummary | undefined;
  isLoading?: boolean;
  className?: string;
  onBarClick?: (payload: {
    key: PerformanceBarKey;
    category: PerformanceBarCategory;
    label: string;
  }) => void;
};

const METRICS = [
  {
    label: "On Time",
    key: "on_time_clock_ins" as const,
    category: "on_time" as const,
    color: "#22C55E",
  },
  {
    label: "Late",
    key: "late_clock_ins" as const,
    category: "late" as const,
    color: "#F59E0B",
  },
  {
    label: "Under Time",
    key: "undertime_shifts" as const,
    category: "undertime" as const,
    color: "#F97316",
  },
  {
    label: "Over Time",
    key: "overtime_shifts" as const,
    category: "overtime" as const,
    color: "#3B82F6",
  },
  {
    label: "Absent",
    key: "absent_shifts" as const,
    category: "absent" as const,
    color: "#EF4444",
  },
] as const;

function hasMeaningfulData(summary: OwnerPerformanceSummary | undefined) {
  if (!summary?.has_performance_data) return false;
  return METRICS.some((metric) => (summary[metric.key] ?? 0) > 0);
}

export function PerformanceOverviewChart({
  summary,
  isLoading,
  className,
  onBarClick,
}: PerformanceOverviewChartProps) {
  const bars = METRICS.map((metric) => ({
    ...metric,
    value: summary?.[metric.key] ?? 0,
  }));
  const hasData = hasMeaningfulData(summary);
  const maxValue = Math.max(...bars.map((bar) => bar.value), 1);

  return (
    <div className={cn("flex min-h-0 flex-1 flex-col", className)}>
      <div className="flex min-h-[11rem] flex-1 items-stretch gap-2 px-1 pb-1">
        {bars.map((bar) => {
          const heightPercent =
            bar.value > 0 ? Math.max(8, Math.round((bar.value / maxValue) * 100)) : 0;

          return (
            <button
              type="button"
              className="flex min-h-0 flex-1 flex-col items-center outline-none transition hover:bg-slate-50 focus-visible:ring-2 focus-visible:ring-[color-mix(in_srgb,var(--owner-navy)_30%,transparent)] rounded-lg"
              key={bar.key}
              onClick={() =>
                onBarClick?.({
                  key: bar.key,
                  category: bar.category,
                  label: bar.label,
                })
              }
            >
              <span className="shrink-0 text-[11px] font-medium text-[#374151]">
                {isLoading ? "..." : bar.value}
              </span>
              <div className="mt-1 flex min-h-0 w-full flex-1 items-end justify-center">
                <div
                  className="w-full max-w-14 rounded-t-md"
                  style={{
                    height: `${heightPercent}%`,
                    minHeight: bar.value > 0 ? 8 : 0,
                    backgroundColor: bar.color,
                  }}
                />
              </div>
              <span className="mt-2 shrink-0 text-center text-[11px] font-medium text-[#6B7280]">
                {bar.label}
              </span>
            </button>
          );
        })}
      </div>

      {!isLoading && !hasData && (
        <div className="mt-3 shrink-0 rounded-xl border border-dashed border-slate-200 bg-[#FAFBFC] px-4 py-2.5 text-center">
          <p className="text-sm font-medium text-[#374151]">
            No attendance records yet.
          </p>
          <p className="mt-1 text-xs text-[#6B7280]">
            Charts will automatically update once employees start timing in.
          </p>
        </div>
      )}
    </div>
  );
}
