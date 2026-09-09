import { useQuery } from "@tanstack/react-query";
import { AttendanceSummary } from "@/components/dashboard/AttendanceSummary";
import { MonthlyRegistrationsChart } from "@/components/dashboard/MonthlyRegistrationsChart";
import { RecentActivities } from "@/components/dashboard/RecentActivities";
import { StatCard } from "@/components/dashboard/StatCard";
import {
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { getDashboardStats } from "@/lib/api";

export function AdminDashboardPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["dashboard-stats"],
    queryFn: getDashboardStats,
  });

  return (
    <AdminPage>
      <AdminPageHeader
        eyebrow="Platform administration"
        title="Dashboard Overview"
        description="Monitor businesses, registrations, and platform activity."
      />

      <AdminPageContent>
        {isError && (
          <p className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            Unable to load dashboard stats. Restart the backend and try again.
          </p>
        )}
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard
            label="Total Business"
            value={data?.total_businesses ?? 0}
            loading={isLoading}
            className="bg-[#1e3a5f]"
          />
          <StatCard
            label="Active Business"
            value={data?.active_businesses ?? 0}
            loading={isLoading}
            className="bg-[#52779C]"
            subtitle="Approved & active"
            to="/admin/approved-business"
          />
          <StatCard
            label="Total Employees"
            value={data?.total_employees ?? 0}
            loading={isLoading}
            className="bg-[#4F93D2]"
          />
          <StatCard
            label="Pendings"
            value={data?.pending_requests ?? 0}
            loading={isLoading}
            className="bg-[#b8d4eb] text-[#1e3a5f]"
            subtitle="Pending requests"
            to="/admin/registrations"
          />
        </div>

        <MonthlyRegistrationsChart
          data={data?.monthly_registrations ?? []}
          loading={isLoading}
        />

        <div className="grid gap-6 lg:grid-cols-2">
          <AttendanceSummary
            present={data?.attendance_summary.present ?? 0}
            absent={data?.attendance_summary.absent ?? 0}
            late={data?.attendance_summary.late ?? 0}
            presentRate={data?.attendance_summary.present_rate ?? 0}
            hasData={data?.attendance_summary.has_data ?? false}
            loading={isLoading}
          />
          <RecentActivities
            activities={data?.recent_activities ?? []}
            loading={isLoading}
          />
        </div>
      </AdminPageContent>
    </AdminPage>
  );
}
