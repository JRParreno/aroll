import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BarChart3,
  BriefcaseBusiness,
  CalendarCheck,
  ClipboardList,
  FileText,
  LayoutDashboard,
  LogOut,
  MapPinned,
  Settings,
  UserRoundCog,
} from "lucide-react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { SignOutConfirmDialog } from "@/components/SignOutConfirmDialog";
import { getMe } from "@/lib/api";
import { clearAuthSession, ME_QUERY_KEY } from "@/lib/authSession";
import { cn } from "@/lib/utils";
import { ownerNavItems } from "@/layouts/ownerNav";

const ownerNavIcons = {
  Dashboard: LayoutDashboard,
  Employees: UserRoundCog,
  Schedule: CalendarCheck,
  Schedules: CalendarCheck,
  Attendance: ClipboardList,
  Payroll: BriefcaseBusiness,
  Location: FileText,
  Locations: FileText,
  Productivity: BarChart3,
  Settings: Settings,
  "Business Setup": Settings,
  Help: MapPinned,
};

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

export function OwnerLayout() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { pathname } = useLocation();
  const [signOutOpen, setSignOutOpen] = useState(false);

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const branding = me?.branding;
  const theme = branding?.theme;
  const sidebarColor = theme?.sidebar_color || "#1E3A5F";
  const activeColor = theme?.secondary_color || "#284B73";
  const businessLogo = branding?.logo_url;
  const ownerProfileImage = branding?.owner_profile_image_url;

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/owner-login");
  }

  return (
    <div className="min-h-screen bg-[#F7F8FA] text-[#1F2937] lg:flex">
      <aside
        className="flex w-full flex-col text-white lg:fixed lg:inset-y-0 lg:z-30 lg:w-64"
        style={{ backgroundColor: sidebarColor }}
      >
        <div className="flex h-24 items-center border-b border-white/10 px-6">
          {businessLogo && (
            <img
              className="mr-3 h-11 w-11 rounded-xl bg-white/10 object-contain p-1"
              src={businessLogo}
              alt={me?.business_name ?? "Business logo"}
            />
          )}
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">
              {me?.business_name ?? "Owner Portal"}
            </p>
            <p className="mt-1 text-[10px] uppercase tracking-[0.16em] text-white/60">
              Business Workspace
            </p>
          </div>
        </div>

        <nav className="flex max-h-[62vh] flex-1 flex-col overflow-y-auto py-4 lg:max-h-none">
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
                  "mx-3 flex h-11 items-center gap-3 rounded-xl px-5 text-[15px] font-medium text-white/75 transition hover:bg-white/10 hover:text-white",
                  active && "bg-[#284B73] text-white shadow-sm"
                )}
                style={active ? { backgroundColor: activeColor } : undefined}
              >
                <Icon className="h-[18px] w-[18px] shrink-0" strokeWidth={2} />
                {item.label}
              </NavLink>
            );
          })}

          <div className="mt-auto px-8 pb-7 pt-4">
            {ownerProfileImage && (
              <div className="mb-4 flex items-center gap-3 rounded-xl bg-white/10 p-3">
                <img
                  className="h-9 w-9 rounded-full object-cover"
                  src={ownerProfileImage}
                  alt={me?.full_name ?? "Owner profile"}
                />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-white">
                    {me?.full_name ?? "Owner"}
                  </p>
                  <p className="text-xs text-white/60">Account owner</p>
                </div>
              </div>
            )}
            <button
              className="flex h-11 w-full items-center gap-3 rounded-xl px-2 text-[15px] font-medium text-white/75 transition hover:bg-white/10 hover:text-white"
              onClick={() => setSignOutOpen(true)}
              type="button"
            >
              <LogOut className="h-[18px] w-[18px]" strokeWidth={2} />
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

      <main className="min-h-screen flex-1 bg-[#F7F8FA] lg:pl-64">
        <Outlet />
      </main>
    </div>
  );
}
