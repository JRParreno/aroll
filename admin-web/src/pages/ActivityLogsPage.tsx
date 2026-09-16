import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ClipboardList, RefreshCw, Search } from "lucide-react";
import {
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { listActivityLogs, type AdminActivityLog } from "@/lib/api";
import { cn } from "@/lib/utils";

const ACTION_LABELS: Record<string, string> = {
  APPROVE_REGISTRATION: "Registration Approved",
  REJECT_REGISTRATION: "Registration Rejected",
};

const ACTION_FILTERS = [
  { value: "all", label: "All Actions" },
  { value: "APPROVE_REGISTRATION", label: "Registration Approved" },
  { value: "REJECT_REGISTRATION", label: "Registration Rejected" },
] as const;

function formatLogDate(value: string) {
  return new Date(value).toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    dateStyle: "medium",
    timeStyle: "short",
  });
}

function formatActionLabel(action: string) {
  return (
    ACTION_LABELS[action] ??
    action
      .replace(/[_-]+/g, " ")
      .toLowerCase()
      .replace(/\b\w/g, (letter) => letter.toUpperCase())
  );
}

function actorEmail(log: AdminActivityLog) {
  return log.actor_email?.trim() || "Unknown admin";
}

function actionTone(action: string) {
  const value = action.toUpperCase();
  if (value.includes("REJECT")) {
    return "bg-[#FBEAEA] text-[#B42318] ring-[#F2C9C6]";
  }
  if (value.includes("APPROVE")) {
    return "bg-[#E8F6EE] text-[#215C36] ring-[#C8E6D2]";
  }
  return "bg-[#E7F0FA] text-[#1E3A5F] ring-[#C9D9EA]";
}

export function ActivityLogsPage() {
  const { data = [], isLoading, isError, refetch, isFetching } = useQuery<
    AdminActivityLog[]
  >({
    queryKey: ["activity-logs"],
    queryFn: listActivityLogs,
  });
  const [query, setQuery] = useState("");
  const [actionFilter, setActionFilter] = useState("all");

  const extraActions = useMemo(() => {
    return Array.from(new Set(data.map((log) => log.action)))
      .filter(
        (action) =>
          action !== "APPROVE_REGISTRATION" && action !== "REJECT_REGISTRATION"
      )
      .sort();
  }, [data]);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return data.filter((log) => {
      if (actionFilter !== "all" && log.action !== actionFilter) return false;
      if (!needle) return true;
      return (
        log.action.toLowerCase().includes(needle) ||
        formatActionLabel(log.action).toLowerCase().includes(needle) ||
        log.description.toLowerCase().includes(needle) ||
        actorEmail(log).toLowerCase().includes(needle)
      );
    });
  }, [actionFilter, data, query]);

  return (
    <AdminPage>
      <AdminPageHeader
        eyebrow="Administration"
        title="Activity Logs"
        description="Platform administration history"
      />

      <AdminPageContent>
        <div className="admin-card px-4 py-3 sm:px-5">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
            <div className="relative min-w-0 flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#9CA3AF]" />
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search activities..."
                className="h-10 rounded-xl border-slate-200 bg-[#F8FAFC] pl-9"
              />
            </div>
            <select
              value={actionFilter}
              onChange={(event) => setActionFilter(event.target.value)}
              className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm text-[#1F2937] outline-none focus-visible:ring-2 focus-visible:ring-[#284B73]/25"
              aria-label="Action"
            >
              <option value="all">All Actions</option>
              {ACTION_FILTERS.filter((item) => item.value !== "all").map((item) => (
                <option key={item.value} value={item.value}>
                  {item.label}
                </option>
              ))}
              {extraActions.map((action) => (
                <option key={action} value={action}>
                  {formatActionLabel(action)}
                </option>
              ))}
            </select>
            <Button
              type="button"
              variant="outline"
              className="h-10 gap-2 rounded-xl"
              onClick={() => void refetch()}
              disabled={isFetching}
            >
              <RefreshCw className={cn("h-4 w-4", isFetching && "animate-spin")} />
              Refresh
            </Button>
          </div>
        </div>

        <section className="admin-card overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[#E8EEF5] bg-[#F8FAFC] px-5 py-3.5">
            <div>
              <p className="text-sm font-semibold text-[#10233A]">Audit trail</p>
              <p className="mt-0.5 text-xs text-[#6B7280]">
                Actions performed by Platform Administrators.
              </p>
            </div>
            <p className="text-xs text-[#6B7280]">
              {isLoading
                ? "Loading logs…"
                : `${filtered.length} of ${data.length} record${data.length === 1 ? "" : "s"}`}
            </p>
          </div>

          {isError && (
            <p className="px-5 py-10 text-sm text-red-700">
              Unable to load activity logs. Try refreshing.
            </p>
          )}

          {isLoading && (
            <div className="divide-y divide-slate-100">
              {[1, 2, 3, 4, 5].map((item) => (
                <div key={item} className="grid grid-cols-4 gap-4 animate-pulse px-5 py-5">
                  <div className="h-4 w-36 rounded bg-slate-200" />
                  <div className="h-4 w-48 rounded bg-slate-100" />
                  <div className="h-4 w-40 rounded bg-slate-100" />
                  <div className="h-4 w-32 rounded bg-slate-100" />
                </div>
              ))}
            </div>
          )}

          {!isLoading && !isError && filtered.length === 0 && (
            <div className="px-6 py-16 text-center">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#E7F0FA] text-[#1E3A5F]">
                <ClipboardList className="h-6 w-6" />
              </div>
              <p className="mt-4 font-medium text-[#1F2937]">
                {data.length === 0 ? "No admin actions recorded yet" : "No matching logs"}
              </p>
              <p className="mt-1 text-sm text-[#6B7280]">
                {data.length === 0
                  ? "Registration approvals and other Platform Admin actions will appear here."
                  : "Try a different search or action filter."}
              </p>
            </div>
          )}

          {!isLoading && !isError && filtered.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] table-fixed text-left">
                <thead className="border-b border-[#E8EEF5] bg-white text-[11px] font-medium uppercase tracking-[0.08em] text-[#6B7280]">
                  <tr>
                    <th className="w-[24%] px-5 py-3">Action</th>
                    <th className="px-5 py-3">Details</th>
                    <th className="w-[22%] px-5 py-3">Admin</th>
                    <th className="w-[22%] px-5 py-3">Time</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((log) => (
                    <tr
                      key={log.id}
                      className="border-b border-slate-100 last:border-0 transition hover:bg-[#F8FAFC]"
                    >
                      <td className="px-5 py-4 align-middle">
                        <span
                          className={cn(
                            "inline-flex max-w-full truncate rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                            actionTone(log.action)
                          )}
                        >
                          {formatActionLabel(log.action)}
                        </span>
                      </td>
                      <td className="px-5 py-4 align-middle text-sm leading-5 text-[#1F2937]">
                        {log.description}
                      </td>
                      <td className="px-5 py-4 align-middle text-sm text-[#1F2937]">
                        <p className="truncate" title={actorEmail(log)}>
                          {actorEmail(log)}
                        </p>
                      </td>
                      <td className="px-5 py-4 align-middle text-sm tabular-nums text-[#6B7280]">
                        {formatLogDate(log.created_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </AdminPageContent>
    </AdminPage>
  );
}
