import { useEffect, useRef, useState } from "react";
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
import type { LucideIcon } from "lucide-react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { SignOutConfirmDialog } from "@/components/SignOutConfirmDialog";
import { getMe } from "@/lib/api";
import { clearAuthSession, ME_QUERY_KEY } from "@/lib/authSession";
import { cn } from "@/lib/utils";
import {
  isOwnerNavItemActive,
  ownerNavItems,
} from "@/layouts/ownerNav";
import { TenantModeBanner } from "@/components/tenant/TenantModeBanner";
import { ResearchEvaluationGate } from "@/components/tenant/ResearchEvaluationGate";
import { sessionIsDemo, sessionIsInternalTest } from "@/lib/tenantMode";

const ownerNavIcons: Record<string, LucideIcon> = {
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

/** Shared visual treatment for all sidebar clickables (nav, profile, logout). */
const ownerSidebarItemClass =
  "group flex h-10 w-full items-center gap-3 rounded-xl px-3 text-[14px] font-medium text-white/70 transition hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/35 focus-visible:ring-offset-0";

const ownerSidebarIconWellClass =
  "flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-white/5 transition group-hover:bg-white/10";

export function OwnerLayout() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { pathname, search } = useLocation();
  const [signOutOpen, setSignOutOpen] = useState(false);
  const mainScrollRef = useRef<HTMLDivElement>(null);

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
  const profileActive =
    pathname === "/owner/profile" || pathname.startsWith("/owner/profile/");

  useEffect(() => {
    mainScrollRef.current?.scrollTo({ top: 0 });
  }, [pathname, search]);

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/owner-login");
  }

  return (
    <div className="owner-shell font-sans flex h-full flex-col text-[#1F2937]">
      <aside
        className="relative flex max-h-56 w-full shrink-0 flex-col text-white lg:fixed lg:inset-y-0 lg:z-30 lg:max-h-none lg:w-64"
        style={{ backgroundColor: sidebarColor }}
      >
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(255,255,255,0.12),transparent_42%)]" />
        <div className="relative flex h-[5.25rem] shrink-0 items-center gap-3 border-b border-white/10 px-5">
          {businessLogo ? (
            <img
              className="h-11 w-11 shrink-0 rounded-full bg-white/10 object-cover ring-2 ring-white/25"
              src={businessLogo}
              alt={me?.business_name ?? "Business logo"}
            />
          ) : (
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-white/15 text-sm font-semibold tracking-wide ring-2 ring-white/20">
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

        <nav className="relative flex min-h-0 flex-1 flex-col overflow-y-auto overflow-x-hidden px-3 py-4">
          <p className="mb-2.5 px-3 text-[10px] font-medium uppercase tracking-[0.16em] text-white/40">
            Menu
          </p>
          <div className="space-y-1.5">
            {ownerNavItems.map((item) => {
              const active = isOwnerNavItemActive(
                pathname,
                item.to,
                item.activePaths
              );
              const Icon = ownerNavIcons[item.label] ?? LayoutDashboard;

              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    ownerSidebarItemClass,
                    active &&
                      "text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
                  )}
                  style={active ? { backgroundColor: activeColor } : undefined}
                >
                  <span
                    className={cn(
                      ownerSidebarIconWellClass,
                      active && "bg-white/15 group-hover:bg-white/15"
                    )}
                  >
                    <Icon className="h-4 w-4 shrink-0" strokeWidth={2} />
                  </span>
                  <span className="min-w-0 flex-1 truncate text-left leading-none">
                    {item.label === "Payroll" && sessionIsDemo(me)
                      ? "Sample Payroll"
                      : item.label}
                  </span>
                </NavLink>
              );
            })}
          </div>

          <div className="mt-auto space-y-1.5 border-t border-white/10 px-0 pb-5 pt-4">
            <button
              className={cn(
                ownerSidebarItemClass,
                "h-auto min-h-10 py-2 text-left",
                profileActive &&
                  "bg-white/10 text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
              )}
              onClick={() => navigate("/owner/profile")}
              type="button"
              aria-current={profileActive ? "page" : undefined}
            >
              {ownerProfileImage ? (
                <img
                  className="h-8 w-8 shrink-0 rounded-lg object-cover ring-1 ring-white/20"
                  src={ownerProfileImage}
                  alt={me?.full_name ?? "Owner profile"}
                />
              ) : (
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-white/15 text-[12px] font-semibold text-white">
                  {(me?.full_name ?? "O").slice(0, 1).toUpperCase()}
                </div>
              )}
              <span className="min-w-0 flex-1 truncate leading-none">
                <span className="block truncate text-[14px] font-medium text-white">
                  {me?.full_name ?? "Owner"}
                </span>
                <span className="mt-0.5 block truncate text-[11px] font-medium text-white/55">
                  View profile
                </span>
              </span>
            </button>
            <button
              className={ownerSidebarItemClass}
              onClick={() => setSignOutOpen(true)}
              type="button"
            >
              <span className={ownerSidebarIconWellClass}>
                <LogOut className="h-4 w-4 shrink-0" strokeWidth={2} />
              </span>
              <span className="min-w-0 flex-1 truncate text-left leading-none">
                Log Out
              </span>
            </button>
          </div>
        </nav>
      </aside>

      <SignOutConfirmDialog
        open={signOutOpen}
        onOpenChange={setSignOutOpen}
        onConfirm={logout}
      />

      <main className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden overflow-x-hidden lg:pl-64">
        <TenantModeBanner />
        <div
          ref={mainScrollRef}
          className="owner-main-scroll"
        >
          <Outlet />
        </div>
      </main>
      <ResearchEvaluationGate />
    </div>
  );
}
