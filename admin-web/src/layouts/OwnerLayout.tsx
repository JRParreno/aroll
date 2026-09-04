import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  CalendarCheck,
  CalendarOff,
  CircleHelp,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  MapPinned,
  Settings,
  Users,
} from "lucide-react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { SignOutConfirmDialog } from "@/components/SignOutConfirmDialog";
import { OwnerNotificationBell } from "@/components/owner/OwnerNotificationBell";
import { getMe } from "@/lib/api";
import { clearAuthSession, ME_QUERY_KEY } from "@/lib/authSession";
import { cn } from "@/lib/utils";
import { ownerNavItems } from "@/layouts/ownerNav";
import { TenantModeBanner } from "@/components/tenant/TenantModeBanner";
import { ResearchEvaluationGate } from "@/components/tenant/ResearchEvaluationGate";
import { sessionIsDemo, sessionIsInternalTest } from "@/lib/tenantMode";

const ownerNavIcons = {
  Dashboard: LayoutDashboard,
  Employees: Users,
  Schedule: CalendarCheck,
  Schedules: CalendarCheck,
  Attendance: ClipboardList,
  "Leave Management": CalendarOff,
  Payroll: BriefcaseBusiness,
  Location: MapPinned,
  Locations: MapPinned,
  Settings: Settings,
  "Business Setup": Settings,
  Help: CircleHelp,
};

const pageMetaByPath: { match: (path: string) => boolean; title: string; subtitle: string }[] = [
  {
    match: (path) => path.startsWith("/owner/notifications"),
    title: "Notifications",
    subtitle: "Stay on top of leave, attendance, and payroll alerts",
  },
  {
    match: (path) => path.startsWith("/owner/profile"),
    title: "Profile",
    subtitle: "Your owner account and workspace identity",
  },
  {
    match: (path) => path.startsWith("/owner/settings/account"),
    title: "Account Settings",
    subtitle: "Manage personal account details",
  },
  {
    match: (path) => path.startsWith("/owner/settings/business"),
    title: "Business Settings",
    subtitle: "Business profile and branding preferences",
  },
  {
    match: (path) => path.startsWith("/owner/settings/leave-policy"),
    title: "Leave Policy",
    subtitle: "Configure leave rules for your team",
  },
  {
    match: (path) => path.startsWith("/owner/settings"),
    title: "Settings",
    subtitle: "Business setup and workspace configuration",
  },
];

function isNavItemActive(
  pathname: string,
  to: string,
  activePaths?: string[]
) {
  if (pathname === to || pathname.startsWith(`${to}/`)) {
    return true;
  }
  return (activePaths ?? []).some(
    (path) => pathname === path || pathname.startsWith(`${path}/`)
  );
}

function resolveTopBarMeta(pathname: string) {
  const special = pageMetaByPath.find((item) => item.match(pathname));
  if (special) {
    return { title: special.title, subtitle: special.subtitle };
  }

  const navItem = ownerNavItems.find((item) =>
    isNavItemActive(pathname, item.to, item.activePaths)
  );

  const subtitles: Record<string, string> = {
    Dashboard: "Overview of attendance, payroll, and setup health",
    Employees: "Enroll, review, and manage your workforce",
    Schedule: "Assign shifts and review the weekly roster",
    Attendance: "Monitor daily time-in and time-out records",
    "Leave Management": "Review and act on employee leave requests",
    Payroll: "Track pay periods and employee earnings",
    Location: "Manage your business attendance location",
    Settings: "Configure setup, policies, and preferences",
    Help: "Guides and support for your workspace",
  };

  return {
    title: navItem?.label ?? "Owner Workspace",
    subtitle: (navItem && subtitles[navItem.label]) || "Business workspace",
  };
}

export function OwnerLayout() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { pathname } = useLocation();
  const [signOutOpen, setSignOutOpen] = useState(false);

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
    refetchOnWindowFocus: true,
  });
  const branding = me?.branding;
  const theme = branding?.theme;
  const sidebarColor = theme?.sidebar_color || "#1E3A5F";
  const activeColor = theme?.secondary_color || "#284B73";
  const businessLogo = branding?.logo_url;
  const ownerProfileImage = branding?.owner_profile_image_url;
  const topBar = useMemo(() => resolveTopBarMeta(pathname), [pathname]);

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/owner-login");
  }

  return (
    <div className="owner-shell min-h-screen text-[#1F2937] lg:flex">
      <aside
        className="relative flex w-full flex-col text-white lg:fixed lg:inset-y-0 lg:z-30 lg:w-64"
        style={{ backgroundColor: sidebarColor }}
      >
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(255,255,255,0.12),transparent_42%)]" />
        <div className="relative flex h-[5.25rem] items-center gap-3 border-b border-white/10 px-5">
          {businessLogo ? (
            <img
              className="h-11 w-11 shrink-0 rounded-full bg-white/10 object-cover ring-2 ring-white/25"
              src={businessLogo}
              alt={me?.business_name ?? "Business logo"}
            />
          ) : (
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-white/15 text-sm font-bold tracking-wide ring-2 ring-white/20">
              {(me?.business_name ?? "A").slice(0, 1).toUpperCase()}
            </div>
          )}
          <div className="min-w-0">
            <p className="truncate text-[15px] font-semibold tracking-tight text-white">
              {me?.business_name ?? "Owner Portal"}
            </p>
            <p className="mt-0.5 text-[10px] font-medium uppercase tracking-[0.16em] text-white/55">
              {sessionIsDemo(me)
                ? "DEMO"
                : sessionIsInternalTest(me)
                  ? "INTERNAL TEST"
                  : "Business Workspace"}
            </p>
          </div>
        </div>

        <nav className="relative flex max-h-[62vh] flex-1 flex-col overflow-y-auto px-3 py-4 lg:max-h-none">
          <p className="mb-2 px-3 text-[10px] font-semibold uppercase tracking-[0.16em] text-white/40">
            Menu
          </p>
          <div className="space-y-1">
            {ownerNavItems.map((item) => {
              const active = isNavItemActive(pathname, item.to, item.activePaths);
              const Icon =
                ownerNavIcons[item.label as keyof typeof ownerNavIcons] ??
                LayoutDashboard;

              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  className={cn(
                    "group flex h-10 items-center gap-3 rounded-xl px-3 text-[14px] font-medium text-white/70 transition",
                    "hover:bg-white/10 hover:text-white",
                    active && "text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
                  )}
                  style={active ? { backgroundColor: activeColor } : undefined}
                >
                  <span
                    className={cn(
                      "flex h-8 w-8 items-center justify-center rounded-lg bg-white/5 transition",
                      active && "bg-white/15",
                      !active && "group-hover:bg-white/10"
                    )}
                  >
                    <Icon className="h-4 w-4 shrink-0" strokeWidth={2} />
                  </span>
                  <span className="truncate">{item.label === "Payroll" && sessionIsDemo(me) ? "Sample Payroll" : item.label}</span>
                </NavLink>
              );
            })}
          </div>

          <div className="mt-auto space-y-3 px-1 pb-5 pt-6">
            <button
              className="flex w-full items-center gap-3 rounded-xl bg-white/10 p-3 text-left transition hover:bg-white/15"
              onClick={() => navigate("/owner/profile")}
              type="button"
            >
              {ownerProfileImage ? (
                <img
                  className="h-9 w-9 rounded-full object-cover ring-2 ring-white/20"
                  src={ownerProfileImage}
                  alt={me?.full_name ?? "Owner profile"}
                />
              ) : (
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-white/20 text-sm font-semibold text-white">
                  {(me?.full_name ?? "O").slice(0, 1).toUpperCase()}
                </div>
              )}
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-white">
                  {me?.full_name ?? "Owner"}
                </p>
                <p className="text-xs text-white/55">View profile</p>
              </div>
            </button>
            <button
              className="flex h-10 w-full items-center gap-3 rounded-xl px-3 text-[14px] font-medium text-white/70 transition hover:bg-white/10 hover:text-white"
              onClick={() => setSignOutOpen(true)}
              type="button"
            >
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/5">
                <LogOut className="h-4 w-4" strokeWidth={2} />
              </span>
              Log Out
            </button>
          </div>
        </nav>
      </aside>

      <SignOutConfirmDialog
        open={signOutOpen}
        onOpenChange={setSignOutOpen}
        onConfirm={logout}
      />

      <main className="min-h-screen flex-1 lg:pl-64">
        <div className="sticky top-0 z-20 border-b border-slate-200/70 bg-white/80 backdrop-blur-md">
          <div className="px-5 py-3 sm:px-8">
            <div className="mx-auto flex max-w-6xl items-center justify-between gap-4">
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-[#1F2937]">
                  {topBar.title}
                </p>
                <p className="truncate text-xs text-[#6B7280]">{topBar.subtitle}</p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <OwnerNotificationBell />
              </div>
            </div>
          </div>
          <TenantModeBanner />
        </div>
        <Outlet />
      </main>
      <ResearchEvaluationGate />
    </div>
  );
}
