import { Clock3 } from "lucide-react";
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
  className?: string;
};

export function AttendanceSummary({
  present,
  absent,
  late,
  presentRate,
  hasData,
  loading,
  className,
}: AttendanceSummaryProps) {
  const display = hasData
    ? { present, absent, late, present_rate: presentRate }
    : MOCK_ATTENDANCE;
  const total = display.present + display.absent + display.late;
  const share = (value: number) =>
    total > 0 ? `${((value / total) * 100).toFixed(1)}%` : "0%";

  return (
    <section className={`admin-card admin-card-pad flex h-full min-h-0 flex-col ${className ?? ""}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <span className="admin-icon-well">
            <Clock3 className="h-4 w-4" strokeWidth={2} />
          </span>
          <div>
            <h2 className="admin-section-kicker">Attendance Summary</h2>
            <p className="admin-section-copy">
              Overview of employee attendance across all businesses.
            </p>
          </div>
        </div>
        {!hasData && !loading && (
          <span className="rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-700">
            Sample data
          </span>
        )}
      </div>

      {loading ? (
        <ShimmerAttendance />
      ) : (
        <div className="mt-4 grid flex-1 grid-cols-3 content-end gap-2">
          <AttendanceStat
            label="Present"
            value={display.present}
            share={hasData ? `${display.present_rate}%` : share(display.present)}
            color="#16A34A"
            well="bg-[#F3FBF6]"
          />
          <AttendanceStat
            label="Late"
            value={display.late}
            share={share(display.late)}
            color="#D97706"
            well="bg-[#FFF8F1]"
          />
          <AttendanceStat
            label="Absent"
            value={display.absent}
            share={share(display.absent)}
            color="#DC2626"
            well="bg-[#FDF4F4]"
          />
        </div>
      )}
    </section>
  );
}

function AttendanceStat({
  label,
  value,
  share,
  color,
  well,
}: {
  label: string;
  value: number;
  share: string;
  color: string;
  well: string;
}) {
  return (
    <div className={`rounded-xl px-2.5 py-2.5 ${well}`}>
      <p className="flex items-center gap-1.5 text-xs font-medium text-[#6B7280]">
        <span className="h-2 w-2 rounded-full" style={{ backgroundColor: color }} />
        {label}
      </p>
      <p className="mt-1.5 text-xl font-semibold tracking-tight text-[#10233A]">
        {value.toLocaleString()}
      </p>
      <p className="mt-1 text-xs text-[#6B7280]">{share}</p>
    </div>
  );
}
