import { useQuery } from "@tanstack/react-query";
import { ClipboardList, RefreshCw } from "lucide-react";
import {
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import {
  listOwnerActivityLogs,
  type OwnerActivityLog,
} from "@/lib/api";
import { cn } from "@/lib/utils";

function formatLogDate(value: string) {
  return new Date(value).toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    dateStyle: "medium",
    timeStyle: "short",
  });
}

function formatActionLabel(action: string) {
  return action
    .replace(/[_-]+/g, " ")
    .toLowerCase()
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function actorLabel(log: OwnerActivityLog) {
  return log.actor?.trim() || "Deleted Account";
}

export function OwnerAuditHistoryPage() {
  const { data = [], isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["owner-activity-logs"],
    queryFn: () => listOwnerActivityLogs(),
  });

  return (
    <OwnerPage>
      <OwnerPageHeader
        back={
          <OwnerPageBackLink to="/owner/settings/setup" label="Business Setup" />
        }
        title="Audit History"
        description="Read-only history of account and workplace activity for your business."
        actions={
          <Button
            type="button"
            variant="outline"
            className="rounded-xl"
            disabled={isFetching}
            onClick={() => refetch()}
          >
            <RefreshCw
              className={cn("mr-2 h-4 w-4", isFetching && "animate-spin")}
            />
            Refresh
          </Button>
        }
      />

      <OwnerPageContent>
        {isLoading ? (
          <p className="text-sm text-[#6B7280]">Loading audit history…</p>
        ) : isError ? (
          <p className="text-sm text-[#B91C1C]">
            Unable to load audit history. Please try again.
          </p>
        ) : data.length === 0 ? (
          <div className="owner-empty">
            <ClipboardList className="mx-auto h-8 w-8 text-[#9CA3AF]" />
            <p className="mt-3 text-sm font-medium text-[#374151]">
              No audit activity yet
            </p>
            <p className="mt-1 text-sm text-[#6B7280]">
              Actions taken in your business will appear here.
            </p>
          </div>
        ) : (
          <div className="owner-card overflow-hidden">
            <div className="hidden grid-cols-[10rem_1fr_12rem] gap-3 border-b border-slate-100 bg-[#F8FAFC] px-4 py-2.5 text-[11px] font-medium uppercase tracking-[0.08em] text-[#6B7280] sm:grid">
              <span>Date / Time</span>
              <span>Activity</span>
              <span>Actor</span>
            </div>
            <ul className="divide-y divide-slate-100">
              {data.map((log) => (
                <li
                  key={log.id}
                  className="grid gap-2 px-4 py-3.5 transition-colors hover:bg-[#F8FAFC] sm:grid-cols-[10rem_1fr_12rem] sm:items-start sm:gap-3"
                >
                  <p className="text-xs text-[#6B7280] sm:text-sm">
                    {formatLogDate(log.created_at)}
                  </p>
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-[#111827]">
                      {formatActionLabel(log.action)}
                    </p>
                    {log.description ? (
                      <p className="mt-0.5 text-sm leading-relaxed text-[#6B7280]">
                        {log.description}
                      </p>
                    ) : null}
                  </div>
                  <p
                    className={cn(
                      "text-sm",
                      log.actor_deleted
                        ? "italic text-[#9CA3AF]"
                        : "text-[#374151]"
                    )}
                  >
                    {actorLabel(log)}
                  </p>
                </li>
              ))}
            </ul>
          </div>
        )}
      </OwnerPageContent>
    </OwnerPage>
  );
}
