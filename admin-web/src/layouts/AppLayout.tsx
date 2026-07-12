import {
  Activity,
  CheckSquare,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  UserRound,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { clearAuthSession } from "@/lib/authSession";
import { cn } from "@/lib/utils";

type NavItem = { to: string; label: string };

const navIcons: Record<string, LucideIcon> = {
  Dashboard: LayoutDashboard,
  "Approved Businesses": CheckSquare,
  "Registration Request": ClipboardList,
  "Activity Logs": Activity,
  Profile: UserRound,
};

export function AppLayout({ nav }: { nav: NavItem[] }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const primaryNav = nav.filter((item) => item.label !== "Profile");
  const profileNav = nav.find((item) => item.label === "Profile");

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/login");
  }

  return (
    <div className="min-h-screen bg-[#F7F8FA] text-[#1F2937] lg:flex">
      <aside className="flex w-full flex-col bg-[#1E3A5F] text-white lg:fixed lg:inset-y-0 lg:z-30 lg:w-64">
        <div className="flex h-20 items-center border-b border-white/10 px-6">
          <p className="text-sm font-semibold uppercase tracking-[0.16em] text-white/75">
            Admin Console
          </p>
        </div>

        <nav className="flex flex-1 flex-col gap-1 px-3 py-5">
          {primaryNav.map((item) => {
            const Icon = navIcons[item.label] ?? LayoutDashboard;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  cn(
                    "flex h-11 items-center gap-3 rounded-xl px-4 text-sm font-medium text-white/75 transition hover:bg-white/10 hover:text-white",
                    isActive && "bg-[#284B73] text-white shadow-sm"
                  )
                }
              >
                <Icon className="h-[18px] w-[18px] shrink-0" strokeWidth={2} />
                <span className="truncate">{item.label}</span>
              </NavLink>
            );
          })}
        </nav>

        <div className="border-t border-white/10 px-3 py-5">
          {profileNav && (
            <NavLink
              key={profileNav.to}
              to={profileNav.to}
              className={({ isActive }) =>
                cn(
                  "mb-2 flex h-11 items-center gap-3 rounded-xl px-4 text-sm font-medium text-white/75 transition hover:bg-white/10 hover:text-white",
                  isActive && "bg-[#284B73] text-white shadow-sm"
                )
              }
            >
              <UserRound className="h-[18px] w-[18px]" strokeWidth={2} />
              Profile
            </NavLink>
          )}
          <button
            className="flex h-11 w-full items-center gap-3 rounded-xl px-4 text-sm font-medium text-white/75 transition hover:bg-white/10 hover:text-white"
            onClick={logout}
            type="button"
          >
            <LogOut className="h-[18px] w-[18px]" strokeWidth={2} />
            Log Out
          </button>
        </div>
      </aside>
      <main className="min-h-screen flex-1 bg-[#F7F8FA] lg:pl-64">
        <Outlet />
      </main>
    </div>
  );
}
