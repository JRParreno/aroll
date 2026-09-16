import { BarChart3 } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  LabelList,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Shimmer, ShimmerChart } from "@/components/ui/shimmer";
import { cn } from "@/lib/utils";

type MonthlyPoint = { month: string; count: number };

type MonthlyRegistrationsChartProps = {
  data: MonthlyPoint[];
  loading?: boolean;
  className?: string;
};

function RegistrationsTooltip({
  active,
  payload,
  label,
}: {
  active?: boolean;
  payload?: { value: number }[];
  label?: string;
}) {
  if (!active || !payload?.length) return null;

  return (
    <div className="rounded-xl border border-[#E8EEF5] bg-white px-3 py-2 shadow-[0_8px_20px_rgba(16,35,58,0.08)]">
      <p className="text-xs text-[#6B7280]">{label}</p>
      <p className="mt-0.5 text-sm font-semibold text-[#1E3A5F]">
        {payload[0].value} registration{payload[0].value === 1 ? "" : "s"}
      </p>
    </div>
  );
}

export function MonthlyRegistrationsChart({
  data,
  loading,
  className,
}: MonthlyRegistrationsChartProps) {
  const chartData = data.length > 0 ? data : [];

  return (
    <section className={cn("admin-card admin-card-pad flex h-full min-h-0 flex-col", className)}>
      {loading ? (
        <Shimmer className="h-9 w-56" />
      ) : (
        <div className="flex items-start gap-3">
          <span className="admin-icon-well">
            <BarChart3 className="h-4 w-4" strokeWidth={2} />
          </span>
          <div>
            <h2 className="admin-section-kicker">Monthly Registrations</h2>
            <p className="admin-section-copy">
              New business registration volume by month.
            </p>
          </div>
        </div>
      )}

      {loading ? (
        <ShimmerChart />
      ) : (
        <div className="mt-3 min-h-[9.5rem] w-full flex-1">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart
              data={chartData}
              barCategoryGap="22%"
              margin={{ top: 18, right: 8, left: -8, bottom: 4 }}
            >
              <CartesianGrid strokeDasharray="4 6" vertical={false} stroke="#E8EEF5" />
              <XAxis
                dataKey="month"
                interval={0}
                tick={{ fontSize: 12, fill: "#6b7280" }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                allowDecimals={false}
                tick={{ fontSize: 12, fill: "#6b7280" }}
                axisLine={false}
                tickLine={false}
                width={28}
              />
              <Tooltip
                cursor={{ fill: "rgba(30, 58, 95, 0.04)" }}
                content={<RegistrationsTooltip />}
              />
              <Bar
                dataKey="count"
                radius={[7, 7, 0, 0]}
                maxBarSize={38}
                minPointSize={6}
              >
                {chartData.map((entry) => (
                  <Cell
                    key={entry.month}
                    fill={entry.count > 0 ? "#3B82F6" : "#D7E4F2"}
                  />
                ))}
                <LabelList
                  dataKey="count"
                  position="top"
                  className="fill-[#6B7280] text-[11px]"
                />
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </section>
  );
}
