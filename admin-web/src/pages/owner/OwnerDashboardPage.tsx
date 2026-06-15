import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { StatCard } from "@/components/dashboard/StatCard";
import { SetupProgressCard } from "@/components/owner/SetupProgressCard";
import { getMe, getSetupStatus, listEmployees } from "@/lib/api";

export function OwnerDashboardPage() {
  const [dismissed, setDismissed] = useState(false);

  const { data: me } = useQuery({
    queryKey: ["me"],
    queryFn: getMe,
  });

  const { data: setupStatus, refetch: refetchSetup } = useQuery({
    queryKey: ["setup-status"],
    queryFn: getSetupStatus,
  });

  const { data: employees = [] } = useQuery({
    queryKey: ["employees"],
    queryFn: listEmployees,
  });

  const businessName = me?.business_name ?? "your business";

  return (
    <div className="min-h-full bg-muted/30 p-6">
      <div className="mx-auto max-w-6xl space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">
            Welcome back, {businessName}
          </h1>
          <p className="mt-1 text-muted-foreground">
            Manage your employees, attendance, payroll, and business operations.
          </p>
        </div>

        {setupStatus && !dismissed && (
          <SetupProgressCard
            status={setupStatus}
            onDismiss={() => {
              setDismissed(true);
              refetchSetup();
            }}
          />
        )}

        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard
            label="Total Employees"
            value={employees.length}
            className="bg-[#1e3a5f]"
          />
          <StatCard label="Present Today" value="—" className="bg-[#5b7c99]" />
          <StatCard label="Absent Today" value="—" className="bg-[#3b9ae8]" />
          <StatCard
            label="Payroll Status"
            value={setupStatus?.setup_completed_at ? "Configured" : "Pending"}
            className="bg-[#b8d4eb] text-[#1e3a5f]"
            subtitle={
              setupStatus
                ? `${setupStatus.completion_percent}% setup complete`
                : "Complete business setup"
            }
          />
        </div>
      </div>
    </div>
  );
}
