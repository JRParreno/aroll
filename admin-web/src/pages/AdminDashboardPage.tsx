import {
  BarChart3,
  Building2,
  CalendarDays,
  CheckCircle2,
  ClipboardList,
  LayoutDashboard,
  Users,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import {
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { AttendanceSummary } from "@/components/dashboard/AttendanceSummary";
import { MonthlyRegistrationsChart } from "@/components/dashboard/MonthlyRegistrationsChart";
import { StatCard } from "@/components/dashboard/StatCard";
import { getDashboardStats } from "@/lib/api";

function formatHeaderDate(value = new Date()) {
  return value.toLocaleDateString("en-PH", {
    timeZone: "Asia/Manila",
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

export function AdminDashboardPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["dashboard-stats"],
    queryFn: getDashboardStats,
  });

  return (
    <AdminPage className="admin-dashboard-page">
      <AdminPageHeader
        eyebrow="Platform Administration"
        title="Admin Dashboard"
        description="Monitor registrations, active businesses, and attendance."
        actions={
          <div className="flex items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2">
            <CalendarDays className="h-4 w-4 text-[#1E3A5F]" />
            <p className="text-xs font-medium text-[#1F2937]">{formatHeaderDate()}</p>
          </div>
        }
      />

      <AdminPageContent className="admin-dashboard-content">
        {isError && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Unable to load dashboard stats. Restart the backend and try again.
          </p>
        )}

        <section className="shrink-0 space-y-3">
          <p className="admin-section-kicker">
            <span className="admin-icon-well h-8 w-8 rounded-lg">
              <LayoutDashboard className="h-4 w-4" strokeWidth={2} />
            </span>
            Snapshot
          </p>
          <div className="grid items-stretch gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              label="Total Businesses"
              value={data?.total_businesses ?? 0}
              loading={isLoading}
              subtitle="All registered businesses"
              icon={Building2}
              tone="navy"
            />
            <StatCard
              label="Active Businesses"
              value={data?.active_businesses ?? 0}
              loading={isLoading}
              subtitle="Approved & active"
              to="/admin/approved-business"
              linkLabel="View approved businesses"
              icon={CheckCircle2}
              tone="green"
            />
            <StatCard
              label="Total Employees"
              value={data?.total_employees ?? 0}
              loading={isLoading}
              subtitle="Across active businesses"
              icon={Users}
              tone="purple"
            />
            <StatCard
              label="Pending Requests"
              value={data?.pending_requests ?? 0}
              loading={isLoading}
              subtitle="Awaiting review"
              to="/admin/registrations"
              linkLabel="View registrations"
              icon={ClipboardList}
              tone="amber"
            />
          </div>
        </section>

        <section className="admin-dashboard-ops">
          <p className="admin-section-kicker shrink-0">
            <span className="admin-icon-well h-8 w-8 rounded-lg">
              <BarChart3 className="h-4 w-4" strokeWidth={2} />
            </span>
            Operations
          </p>
          <div className="admin-dashboard-ops-grid grid items-stretch gap-4 lg:grid-cols-3">
            <div className="h-full min-h-0 min-w-0 lg:col-span-2">
              <MonthlyRegistrationsChart
                data={data?.monthly_registrations ?? []}
                loading={isLoading}
              />
            </div>
            <div className="h-full min-h-0 min-w-0">
              <AttendanceSummary
                present={data?.attendance_summary.present ?? 0}
                absent={data?.attendance_summary.absent ?? 0}
                late={data?.attendance_summary.late ?? 0}
                presentRate={data?.attendance_summary.present_rate ?? 0}
                hasData={data?.attendance_summary.has_data ?? false}
                loading={isLoading}
              />
            </div>
          </div>
        </section>
      </AdminPageContent>
    </AdminPage>
  );
}
