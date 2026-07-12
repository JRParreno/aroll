import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Shimmer, ShimmerChart } from "@/components/ui/shimmer";

const BAR_COLORS = [
  "#3B82F6",
  "#F59E0B",
  "#EF4444",
  "#16A34A",
  "#8B5CF6",
  "#D97706",
  "#0891B2",
  "#DB2777",
  "#4F46E5",
  "#0F766E",
  "#B45309",
  "#7C3AED",
];

type MonthlyRegistrationsChartProps = {
  data: { month: string; count: number }[];
  loading?: boolean;
};

export function MonthlyRegistrationsChart({
  data,
  loading,
}: MonthlyRegistrationsChartProps) {
  const chartData = data.length > 0 ? data : [];

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
      {loading ? (
        <Shimmer className="h-6 w-48" />
      ) : (
        <div>
          <h2 className="text-lg font-semibold text-[#1F2937]">
            Monthly Registrations
          </h2>
          <p className="mt-1 text-sm text-[#6B7280]">
            New business registration volume by month.
          </p>
        </div>
      )}

      {loading ? (
        <ShimmerChart />
      ) : (
        <div className="mt-6 h-64 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartData} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#E5E7EB" />
              <XAxis
                dataKey="month"
                tick={{ fontSize: 12, fill: "#6b7280" }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                allowDecimals={false}
                tick={{ fontSize: 12, fill: "#6b7280" }}
                axisLine={false}
                tickLine={false}
              />
              <Tooltip
                cursor={{ fill: "rgba(0,0,0,0.04)" }}
                contentStyle={{
                  borderRadius: "12px",
                  border: "1px solid #E5E7EB",
                  boxShadow: "0 10px 24px rgba(15, 23, 42, 0.08)",
                  fontSize: "13px",
                }}
              />
              <Bar dataKey="count" radius={[6, 6, 0, 0]} maxBarSize={36}>
                {chartData.map((_, index) => (
                  <Cell key={index} fill={BAR_COLORS[index % BAR_COLORS.length]} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}
