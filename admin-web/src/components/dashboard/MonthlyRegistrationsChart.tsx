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
  "#2563eb",
  "#f97316",
  "#ef4444",
  "#22c55e",
  "#a855f7",
  "#eab308",
  "#06b6d4",
  "#ec4899",
  "#6366f1",
  "#14b8a6",
  "#f59e0b",
  "#8b5cf6",
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
    <div className="rounded-2xl border bg-card p-6 shadow-sm">
      {loading ? (
        <Shimmer className="mx-auto h-6 w-48" />
      ) : (
        <h2 className="text-center text-lg font-semibold">Monthly Registrations</h2>
      )}

      {loading ? (
        <ShimmerChart />
      ) : (
        <div className="mt-6 h-64 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartData} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e5e7eb" />
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
                  borderRadius: "8px",
                  border: "1px solid #e5e7eb",
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
