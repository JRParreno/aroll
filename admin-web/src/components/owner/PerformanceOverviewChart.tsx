import type { OwnerPerformanceSummary } from "@/lib/api";

type PerformanceOverviewChartProps = {
  summary: OwnerPerformanceSummary | undefined;
  isLoading?: boolean;
  className?: string;
};

const METRICS = [
  { label: "On time", key: "on_time_clock_ins" as const, color: "#22C55E" },
  { label: "Late", key: "late_clock_ins" as const, color: "#F59E0B" },
  { label: "Under", key: "undertime_shifts" as const, color: "#F97316" },
  { label: "Over", key: "overtime_shifts" as const, color: "#3B82F6" },
  { label: "Absent", key: "absent_shifts" as const, color: "#EF4444" },
] as const;

const MAX_BAR_HEIGHT = 140;

export function PerformanceOverviewChart({
  summary,
  isLoading,
  className,
}: PerformanceOverviewChartProps) {
  const bars = METRICS.map((metric) => ({
    ...metric,
    value: summary?.[metric.key] ?? 0,
  }));
  const maxValue = Math.max(...bars.map((bar) => bar.value), 1);

  return (
    <div className={className}>
      <div className="flex h-[180px] items-end gap-2 px-1">
        {bars.map((bar) => {
          const barHeight =
            bar.value > 0
              ? Math.max(8, Math.round((bar.value / maxValue) * MAX_BAR_HEIGHT))
              : 0;

          return (
            <div
              className="flex flex-1 flex-col items-center justify-end"
              key={bar.key}
            >
              <span className="text-[10px] font-semibold text-[#374151]">
                {isLoading ? "..." : bar.value}
              </span>
              <div
                className="mt-1 w-full max-w-14 rounded-t-md"
                style={{
                  height: `${barHeight}px`,
                  backgroundColor: bar.color,
                }}
              />
              <span className="mt-2 text-center text-[10px] text-[#6B7280]">
                {bar.label}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
