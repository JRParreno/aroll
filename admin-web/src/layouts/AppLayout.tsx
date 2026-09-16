import { useEffect, useRef, useState } from "react";
import {
  Activity,
  CheckSquare,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  Scale,
  UserRound,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { SignOutConfirmDialog } from "@/components/SignOutConfirmDialog";
import { clearAuthSession } from "@/lib/authSession";
import { cn } from "@/lib/utils";

type NavItem = { to: string; label: string };

const navIcons: Record<string, LucideIcon> = {
  Dashboard: LayoutDashboard,
  "Approved Businesses": CheckSquare,
  "Registration Request": ClipboardList,
  Consents: Scale,
  "Legal Defaults": Scale,
  "Activity Logs": Activity,
  Profile: UserRound,
};

export function AppLayout({ nav }: { nav: NavItem[] }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { pathname } = useLocation();
  const [signOutOpen, setSignOutOpen] = useState(false);
  const mainScrollRef = useRef<HTMLDivElement>(null);
  const primaryNav = nav.filter((item) => item.label !== "Profile");
  const profileNav = nav.find((item) => item.label === "Profile");
  const isDashboard =
    pathname === "/admin/dashboard" || pathname === "/admin";

  useEffect(() => {
    mainScrollRef.current?.scrollTo({ top: 0 });
  }, [pathname]);

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/login");
  }

  return (
    <div className="admin-shell text-[#1F2937]">
      <aside className="admin-sidebar">
        <div className="flex h-[4.5rem] shrink-0 items-center gap-3 border-b border-white/10 px-5">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white text-sm font-semibold text-[#16324F]">
            A
          </span>
          <div className="min-w-0">
            <p className="truncate text-[15px] font-semibold tracking-tight text-white">
              Aroll+
            </p>
            <p className="mt-0.5 text-[10px] font-medium uppercase tracking-[0.16em] text-white/55">
              Admin Console
            </p>
          </div>
        </div>

        <nav className="admin-nav-list" aria-label="Admin">
          {primaryNav.map((item) => {
            const Icon = navIcons[item.label] ?? LayoutDashboard;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  cn("admin-nav-item", isActive && "admin-nav-item-active")
                }
              >
                <Icon strokeWidth={2} />
                <span className="admin-nav-item-label">{item.label}</span>
              </NavLink>
            );
          })}
        </nav>

        <div className="admin-nav-footer">
          {profileNav && (
            <NavLink
              to={profileNav.to}
              className={({ isActive }) =>
                cn("admin-nav-item", isActive && "admin-nav-item-active")
              }
            >
              <UserRound strokeWidth={2} />
              <span className="admin-nav-item-label">{profileNav.label}</span>
            </NavLink>
          )}
          <button
            className="admin-nav-item"
            onClick={() => setSignOutOpen(true)}
            type="button"
          >
            <LogOut strokeWidth={2} />
            <span className="admin-nav-item-label">Log Out</span>
          </button>
        </div>
      </aside>
      <SignOutConfirmDialog
        open={signOutOpen}
        onOpenChange={setSignOutOpen}
        onConfirm={logout}
      />
      <main className="admin-main">
        <div
          ref={mainScrollRef}
          className={cn("admin-main-scroll", isDashboard && "admin-dashboard-scroll")}
        >
          <Outlet />
        </div>
      </main>
    </div>
  );
}
