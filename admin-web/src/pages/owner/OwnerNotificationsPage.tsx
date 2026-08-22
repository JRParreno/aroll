import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { Bell, CheckCheck } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  type Notification,
} from "@/lib/api";
import { cn } from "@/lib/utils";

export function OwnerNotificationsPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();

  const { data: notifications = [], isLoading } = useQuery({
    queryKey: ["notifications"],
    queryFn: () => listNotifications({ limit: 50 }),
  });

  const markRead = useMutation({
    mutationFn: markNotificationRead,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["notifications"] });
    },
  });

  const markAllRead = useMutation({
    mutationFn: markAllNotificationsRead,
    onSuccess: (result) => {
      toast.success(
        result.marked_read > 0
          ? `Marked ${result.marked_read} notification(s) as read`
          : "All caught up"
      );
      void qc.invalidateQueries({ queryKey: ["notifications"] });
    },
    onError: () => toast.error("Failed to mark notifications as read"),
  });

  async function handleNotificationClick(notification: Notification) {
    if (!notification.is_read) {
      await markRead.mutateAsync(notification.id);
    }
    if (notification.deep_link) {
      navigate(notification.deep_link);
    }
  }

  const unreadCount = notifications.filter((item) => !item.is_read).length;

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Notifications"
        description="Stay on top of leave requests, schedule changes, and other updates."
        actions={
          unreadCount > 0 ? (
            <Button
              variant="outline"
              className="gap-2"
              disabled={markAllRead.isPending}
              onClick={() => markAllRead.mutate()}
            >
              <CheckCheck className="h-4 w-4" />
              Mark all read
            </Button>
          ) : null
        }
      />
      <OwnerPageContent>
        {isLoading ? (
          <p className="text-sm text-muted-foreground">Loading notifications…</p>
        ) : notifications.length === 0 ? (
          <div className="rounded-2xl border border-slate-200 bg-white p-8 text-center shadow-sm">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-slate-100 text-[#6B7280]">
              <Bell className="h-5 w-5" />
            </div>
            <p className="font-medium text-[#111827]">No notifications yet</p>
            <p className="mt-1 text-sm text-[#6B7280]">
              Updates about leave and scheduling will appear here.
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {notifications.map((notification) => (
              <button
                key={notification.id}
                className={cn(
                  "w-full rounded-2xl border bg-white p-4 text-left shadow-sm transition hover:shadow-md",
                  notification.is_read
                    ? "border-slate-200"
                    : "border-[#1F456B]/30 bg-[#F8FAFC]"
                )}
                onClick={() => void handleNotificationClick(notification)}
                type="button"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-semibold text-[#111827]">
                      {notification.title}
                    </p>
                    <p className="mt-1 text-sm text-[#6B7280]">
                      {notification.message}
                    </p>
                  </div>
                  {!notification.is_read ? (
                    <span className="mt-1 h-2.5 w-2.5 shrink-0 rounded-full bg-[#1F456B]" />
                  ) : null}
                </div>
                <p className="mt-2 text-xs text-[#9CA3AF]">
                  {formatDistanceToNow(new Date(notification.created_at), {
                    addSuffix: true,
                  })}
                </p>
              </button>
            ))}
          </div>
        )}
      </OwnerPageContent>
    </OwnerPage>
  );
}
