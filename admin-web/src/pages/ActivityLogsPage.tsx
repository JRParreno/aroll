import { useQuery } from "@tanstack/react-query";
import { Activity, Clock3 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
    <div className="min-h-full bg-[#F7F8FA]">
      <header className="border-b border-slate-200 bg-white px-5 py-6 sm:px-8">
        <div className="mx-auto max-w-6xl">
          <p className="text-sm font-medium text-[#6B7280]">
            Platform history
          </p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight text-[#1F2937] sm:text-3xl">
            Activity Logs
          </h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-[#6B7280]">
            Review recent platform actions and registration activity.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
        <Card className="overflow-hidden rounded-2xl border-slate-200 bg-white shadow-sm">
          <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle className="text-base font-semibold text-[#1F2937]">
                  Log Entries
                </CardTitle>
                <p className="mt-1 text-sm text-[#6B7280]">
                  {isLoading
                    ? "Loading logs..."
                    : `${data.length} recorded event${data.length === 1 ? "" : "s"}`}
                </p>
              </div>
              <span className="rounded-full bg-[#EAF2FB] px-3 py-1 text-xs font-medium text-[#1E3A5F]">
                Audit trail
              </span>
            </div>
          </CardHeader>

          <CardContent className="p-0">
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
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#EAF2FB] text-[#1E3A5F]">
                  <Activity className="h-6 w-6" />
                </div>
                <p className="mt-4 font-medium text-[#1F2937]">
                  No activity recorded yet
                </p>
                <p className="mt-1 text-sm text-[#6B7280]">
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
                      <p className="mt-3 text-sm leading-6 text-[#1F2937]">
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
          </CardContent>
        </Card>
      </main>
    </div>
  );
}
