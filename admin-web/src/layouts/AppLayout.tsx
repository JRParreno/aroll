import { useEffect, useRef, useState } from "react";
import {
  Activity,
  CheckSquare,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  UserRound,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { SignOutConfirmDialog } from "@/components/SignOutConfirmDialog";
import { getMe } from "@/lib/api";
import { clearAuthSession, ME_QUERY_KEY } from "@/lib/authSession";
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
  const { pathname, search } = useLocation();
  const [signOutOpen, setSignOutOpen] = useState(false);
  const mainScrollRef = useRef<HTMLDivElement>(null);
  const primaryNav = nav.filter((item) => item.label !== "Profile");
  const profileNav = nav.find((item) => item.label === "Profile");
  const profileTo = profileNav?.to ?? "/admin/profile";
  const profileActive =
    pathname === profileTo || pathname.startsWith(`${profileTo}/`);

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
    refetchOnWindowFocus: true,
  });

  useEffect(() => {
    mainScrollRef.current?.scrollTo({ top: 0 });
  }, [pathname, search]);

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/login");
  }

  return (
    <div className="admin-shell font-sans flex h-full flex-col text-[#1F2937]">
      <aside className="relative flex max-h-[42vh] w-full shrink-0 flex-col bg-[#1E3A5F] text-white lg:fixed lg:inset-y-0 lg:z-30 lg:max-h-none lg:w-64">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(255,255,255,0.12),transparent_42%)]" />
        <div className="relative flex h-[5.25rem] shrink-0 items-center gap-3 border-b border-white/10 px-5">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-white/15 text-sm font-semibold tracking-wide ring-2 ring-white/20">
            A
          </div>
          <div className="min-w-0">
            <p className="truncate text-[15px] font-semibold tracking-tight text-white">
              Admin Console
            </p>
            <p className="mt-0.5 text-[10px] font-medium uppercase tracking-[0.16em] text-white/55">
              Platform Administration
            </p>
          </div>
        </div>

        <nav className="relative flex min-h-0 flex-1 flex-col overflow-y-auto overflow-x-hidden px-3 py-4">
          <p className="mb-2 px-3 text-[10px] font-medium uppercase tracking-[0.16em] text-white/40">
            Menu
          </p>
          <div className="space-y-1">
            {primaryNav.map((item) => {
              const Icon = navIcons[item.label] ?? LayoutDashboard;
              const active =
                pathname === item.to || pathname.startsWith(`${item.to}/`);

              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "group flex h-10 items-center gap-3 rounded-xl px-3 text-[14.5px] font-medium text-white/70 transition",
                    "hover:bg-white/10 hover:text-white",
                    active &&
                      "bg-[#284B73] text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
                  )}
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
                  <span className="truncate">{item.label}</span>
                </NavLink>
              );
            })}
          </div>

          <div className="mt-auto space-y-3 px-1 pb-5 pt-6">
            {profileNav ? (
              <button
                className={cn(
                  "flex w-full items-center gap-3 rounded-xl bg-white/10 p-3 text-left transition hover:bg-white/15",
                  profileActive && "ring-1 ring-white/25"
                )}
                onClick={() => navigate(profileTo)}
                type="button"
                aria-current={profileActive ? "page" : undefined}
              >
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-white/20 text-sm font-semibold text-white">
                  {(me?.full_name ?? "A").slice(0, 1).toUpperCase()}
                </div>
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-white">
                    {me?.full_name ?? "Administrator"}
                  </p>
                  <p className="text-xs font-medium text-white/55">
                    View profile
                  </p>
                </div>
              </button>
            ) : null}
            <button
              className="flex h-10 w-full items-center gap-3 rounded-xl px-3 text-[14.5px] font-medium text-white/70 transition hover:bg-white/10 hover:text-white"
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

      <main className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden overflow-x-hidden lg:pl-64">
        <div ref={mainScrollRef} className="admin-main-scroll">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
