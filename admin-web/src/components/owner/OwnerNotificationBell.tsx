import { useQuery } from "@tanstack/react-query";
import { Bell } from "lucide-react";
import { Link } from "react-router-dom";
import { getNotificationUnreadCount } from "@/lib/api";
import { cn } from "@/lib/utils";

export function OwnerNotificationBell({ className }: { className?: string }) {
  const { data: unreadCount = 0 } = useQuery({
    queryKey: ["notifications", "unread-count"],
    queryFn: getNotificationUnreadCount,
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
  });

  return (
    <Link
      to="/owner/notifications"
      className={cn(
        "relative inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-200/90 bg-white text-[#374151] shadow-sm transition hover:border-[#1E3A5F]/20 hover:bg-[#F8FAFC] hover:text-[#1E3A5F]",
        className
      )}
      aria-label={
        unreadCount > 0
          ? `${unreadCount} unread notifications`
          : "Notifications"
      }
    >
      <Bell className="h-[18px] w-[18px]" strokeWidth={2} />
      {unreadCount > 0 ? (
        <span className="absolute -right-1.5 -top-1.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-[#DC2626] px-1 text-[10px] font-bold text-white ring-2 ring-white">
          {unreadCount > 99 ? "99+" : unreadCount}
        </span>
      ) : null}
    </Link>
  );
}
