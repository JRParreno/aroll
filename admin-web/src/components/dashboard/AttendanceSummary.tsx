import { ShimmerAttendance } from "@/components/ui/shimmer";

const MOCK_ATTENDANCE = {
  present: 1150,
  absent: 25,
  late: 30,
  present_rate: 93.8,
};

type AttendanceSummaryProps = {
  present: number;
  absent: number;
  late: number;
  presentRate: number;
  hasData: boolean;
  loading?: boolean;
};

export function AttendanceSummary({
  present,
  absent,
  late,
  presentRate,
  hasData,
  loading,
}: AttendanceSummaryProps) {
  const display = hasData
    ? { present, absent, late, present_rate: presentRate }
    : MOCK_ATTENDANCE;

  const radius = 68;
  const circumference = 2 * Math.PI * radius;
  const progress = (display.present_rate / 100) * circumference;

  return (
    <div className="rounded-2xl border bg-card p-6 shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-lg font-semibold">Today&apos;s Attendance Summary</h2>
        {!hasData && !loading && (
          <span className="rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-700">
            Sample data
          </span>
        )}
      </div>

      {loading ? (
        <ShimmerAttendance />
      ) : (
        <div className="mt-4 flex flex-col items-center gap-6 sm:flex-row sm:items-center">
          <div className="relative h-44 w-44 shrink-0">
            <svg
              viewBox="0 0 160 160"
              className="h-full w-full -rotate-90"
              aria-hidden
            >
              <circle
                cx="80"
                cy="80"
                r={radius}
                fill="none"
                stroke="#e5e7eb"
                strokeWidth="14"
              />
              <circle
                cx="80"
                cy="80"
                r={radius}
                fill="none"
                stroke="#22c55e"
                strokeWidth="14"
                strokeLinecap="round"
                strokeDasharray={`${progress} ${circumference}`}
              />
            </svg>
            <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-2xl font-bold text-emerald-600">
                {display.present_rate}%
              </span>
              <span className="text-xs text-muted-foreground">Present Rate</span>
            </div>
          </div>

          <div className="w-full space-y-4 sm:flex-1">
            <AttendanceStat label="Present" value={display.present} color="text-emerald-600" />
            <AttendanceStat label="Absent" value={display.absent} color="text-red-500" />
            <AttendanceStat label="Late" value={display.late} color="text-amber-500" />
          </div>
        </div>
      )}
    </div>
  );
}

function AttendanceStat({
  label,
  value,
  color,
}: {
  label: string;
  value: number;
  color: string;
}) {
  return (
    <div className="flex items-baseline justify-between border-b border-dashed pb-2 last:border-0">
      <span className={`text-2xl font-bold ${color}`}>
        {value.toLocaleString()}
      </span>
      <span className="text-sm text-muted-foreground">{label}</span>
    </div>
  );
}
