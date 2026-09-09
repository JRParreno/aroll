import { useQuery } from "@tanstack/react-query";
import { Activity, Clock3 } from "lucide-react";
import {
  AdminCard,
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { listActivityLogs } from "@/lib/api";

type ActivityLog = {
  id: string;
  action: string;
  description: string;
  created_at: string;
};

function formatLogDate(value: string) {
  return new Date(value).toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function ActivityLogsPage() {
  const { data = [], isLoading } = useQuery<ActivityLog[]>({
    queryKey: ["activity-logs"],
    queryFn: listActivityLogs,
  });

  return (
    <AdminPage>
      <AdminPageHeader
        eyebrow="Platform history"
        title="Activity Logs"
        description="Review recent platform actions and registration activity."
      />

      <AdminPageContent>
        <AdminCard className="overflow-hidden">
          <div className="border-b border-slate-200/80 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="owner-section-title">Log Entries</h2>
                <p className="owner-section-subtitle mt-1">
                  {isLoading
                    ? "Loading logs..."
                    : `${data.length} recorded event${data.length === 1 ? "" : "s"}`}
                </p>
              </div>
              <span className="rounded-full bg-[#EAF2FB] px-3 py-1 text-xs font-medium text-[#1E3A5F]">
                Audit trail
              </span>
            </div>
          </div>

          {isLoading && (
            <div className="divide-y divide-slate-100">
              {[1, 2, 3].map((i) => (
                <div key={i} className="animate-pulse p-5">
                  <div className="h-4 w-44 rounded bg-slate-200" />
                  <div className="mt-3 h-3 w-80 max-w-full rounded bg-slate-100" />
                </div>
              ))}
            </div>
          )}

          {!isLoading && data.length === 0 && (
            <div className="px-6 py-14 text-center">
              <div className="owner-icon-well mx-auto h-12 w-12">
                <Activity className="h-6 w-6" />
              </div>
              <p className="owner-section-title mt-4">No activity recorded yet</p>
              <p className="owner-section-subtitle mt-1">
                Platform actions will appear here as they are recorded.
              </p>
            </div>
          )}

          {!isLoading && data.length > 0 && (
            <div className="divide-y divide-slate-100">
              {data.map((log) => (
                <article
                  key={log.id}
                  className="grid gap-3 p-5 sm:grid-cols-[1fr_auto] sm:items-start"
                >
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-full bg-[#EAF2FB] px-3 py-1 text-xs font-medium text-[#1E3A5F]">
                        {log.action}
                      </span>
                    </div>
                    <p className="mt-3 text-[0.9375rem] leading-6 text-[#1F2937]">
                      {log.description}
                    </p>
                  </div>

                  <p className="inline-flex items-center gap-1.5 text-sm text-[#6B7280]">
                    <Clock3 className="h-4 w-4" />
                    {formatLogDate(log.created_at)}
                  </p>
                </article>
              ))}
            </div>
          )}
        </AdminCard>
      </AdminPageContent>
    </AdminPage>
  );
}
