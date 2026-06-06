import { formatDateTime } from "@/components/detail/DetailLayout";
import { ShimmerActivityList } from "@/components/ui/shimmer";

type Activity = {
  id: string;
  description: string;
  created_at: string;
};

type RecentActivitiesProps = {
  activities: Activity[];
  loading?: boolean;
};

const MOCK_ACTIVITIES: Activity[] = [
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

function formatTime(value: string) {
  return new Date(value).toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    timeStyle: "short",
  });
}

export function RecentActivities({ activities, loading }: RecentActivitiesProps) {
  const items = activities.length > 0 ? activities : MOCK_ACTIVITIES;
  const isSample = activities.length === 0 && !loading;

  return (
    <div className="rounded-2xl border bg-card p-6 shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-lg font-semibold">Recent Activities</h2>
        {isSample && (
          <span className="rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-700">
            Sample data
          </span>
        )}
      </div>

      {loading ? (
        <ShimmerActivityList />
      ) : (
        <div className="mt-4 space-y-3">
          {items.map((activity) => (
            <div
              key={activity.id}
              className="flex items-center justify-between gap-3 rounded-xl border bg-background px-4 py-3 shadow-sm"
            >
              <p className="text-sm font-medium text-blue-700">
                {activity.description}
              </p>
              <span className="shrink-0 text-xs text-muted-foreground">
                {formatTime(activity.created_at)}
              </span>
            </div>
          ))}
        </div>
      )}

      {!loading && activities.length > 0 && (
        <p className="mt-3 text-xs text-muted-foreground">
          Last updated {formatDateTime(activities[0]?.created_at)}
        </p>
      )}
    </div>
  );
}
