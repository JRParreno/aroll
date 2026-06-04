import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { listActivityLogs } from "@/lib/api";

export function ActivityLogsPage() {
  const { data = [], isLoading } = useQuery({
    queryKey: ["activity-logs"],
    queryFn: listActivityLogs,
  });

  return (
    <div className="p-6">
      <Card>
        <CardHeader>
          <CardTitle>Activity Logs</CardTitle>
        </CardHeader>

        <CardContent className="space-y-3">
          {isLoading && (
            <p className="text-muted-foreground">Loading logs...</p>
          )}

          {!isLoading && data.length === 0 && (
            <p className="text-muted-foreground">No activity recorded yet.</p>
          )}

          {data.map((log: any) => (
            <div
              key={log.id}
              className="border rounded-md p-3 space-y-1"
            >
              {/* Action */}
              <p className="font-semibold text-sm">
                {log.action}
              </p>

              {/* Description */}
              <p className="text-sm text-muted-foreground">
                {log.description}
              </p>

              {/* Timestamp */}
              <p className="text-xs text-gray-400">
                {new Date(log.created_at).toLocaleString("en-PH", {
                timeZone: "Asia/Manila",
                dateStyle: "medium",
                timeStyle: "short",
                })}
              </p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}