import { Activity, CheckCircle2, ClipboardList, Scale, UserPlus } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Link } from "react-router-dom";
import { ShimmerActivityList } from "@/components/ui/shimmer";

type ActivityItem = {
  id: string;
  description: string;
  created_at: string;
};

type RecentActivitiesProps = {
  activities: ActivityItem[];
  loading?: boolean;
};

const MOCK_ACTIVITIES: ActivityItem[] = [
  {
    id: "mock-1",
    description: "Approval of Mr. Beans Cafe",
    created_at: new Date().toISOString(),
  },
  {
    id: "mock-2",
    description: "Approval of Ugom Cafe",
    created_at: new Date(Date.now() - 3600000).toISOString(),
  },
  {
    id: "mock-3",
    description: "Approval of Pande Doc",
    created_at: new Date(Date.now() - 7200000).toISOString(),
  },
  {
    id: "mock-4",
    description: "Approval of Benzon Burger House",
    created_at: new Date(Date.now() - 86400000).toISOString(),
  },
];

function relativeTime(value: string) {
  const delta = Date.now() - new Date(value).getTime();
  const minutes = Math.max(1, Math.round(delta / 60000));
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

function activityVisual(description: string): { icon: LucideIcon; className: string } {
  const text = description.toLowerCase();
  if (text.includes("approv")) {
    return { icon: CheckCircle2, className: "bg-[#E8F6EE] text-[#2F7D4A]" };
  }
  if (text.includes("reject")) {
    return { icon: ClipboardList, className: "bg-[#FBEAEA] text-[#B42318]" };
  }
  if (text.includes("employee")) {
    return { icon: UserPlus, className: "bg-[#F8EEE6] text-[#C56A2D]" };
  }
  if (
    text.includes("consent") ||
    text.includes("terms") ||
    text.includes("privacy") ||
    text.includes("biometric")
  ) {
    return { icon: Scale, className: "bg-[#E7F0FA] text-[#1E3A5F]" };
  }
  return { icon: Activity, className: "bg-[#E7F0FA] text-[#1E3A5F]" };
}

export function RecentActivities({ activities, loading }: RecentActivitiesProps) {
  const source = activities.length > 0 ? activities : MOCK_ACTIVITIES;
  const items = source.slice(0, 5);
  const isSample = activities.length === 0 && !loading;

  return (
    <section className="admin-card admin-card-pad">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <span className="admin-icon-well">
            <Activity className="h-4 w-4" strokeWidth={2} />
          </span>
          <div>
            <h2 className="admin-section-kicker">Recent Activities</h2>
            <p className="admin-section-copy">Latest system activities and updates.</p>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-2 pt-1">
          {isSample && (
            <span className="rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-700">
              Sample data
            </span>
          )}
          <Link
            to="/admin/activity-logs"
            className="rounded-lg px-2.5 py-1 text-xs font-medium text-[#1E3A5F] transition hover:bg-[#E7F0FA]"
          >
            View all
          </Link>
        </div>
      </div>

      {loading ? (
        <ShimmerActivityList />
      ) : (
        <div className="mt-4">
          {items.map((activity) => {
            const visual = activityVisual(activity.description);
            const Icon = visual.icon;
            return (
              <div
                key={activity.id}
                className="-mx-2 flex min-h-14 items-center gap-3 rounded-xl border-b border-slate-100 px-2 py-2.5 last:border-0 transition hover:bg-[#F8FAFC]"
              >
                <span
                  className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full ${visual.className}`}
                >
                  <Icon className="h-3.5 w-3.5" strokeWidth={2.25} />
                </span>
                <p className="min-w-0 flex-1 truncate text-sm leading-5 text-[#1F2937]">
                  {activity.description}
                </p>
                <span className="shrink-0 text-xs tabular-nums text-[#6B7280]">
                  {relativeTime(activity.created_at)}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
