import { useEffect, useRef, useState } from "react";
import {
  Activity,
  CheckSquare,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  Menu,
  Scale,
  UserRound,
  X,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { SignOutConfirmDialog } from "@/components/SignOutConfirmDialog";
import { clearAuthSession } from "@/lib/authSession";
import { useDesktopNav } from "@/layouts/useDesktopNav";
import { cn } from "@/lib/utils";

type NavItem = { to: string; label: string };

const navIcons: Record<string, LucideIcon> = {
  Dashboard: LayoutDashboard,
  "Approved Businesses": CheckSquare,
  "Recently Approved": CheckSquare,
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
  const [menuOpen, setMenuOpen] = useState(false);
  const desktopNav = useDesktopNav();
  const sidebarRef = useRef<HTMLElement>(null);
  const mainScrollRef = useRef<HTMLDivElement>(null);
  const primaryNav = nav.filter((item) => item.label !== "Profile");
  const profileNav = nav.find((item) => item.label === "Profile");
  const isDashboard =
    pathname === "/admin/dashboard" || pathname === "/admin";

  useEffect(() => {
    mainScrollRef.current?.scrollTo({ top: 0 });
    setMenuOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!menuOpen) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setMenuOpen(false);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [menuOpen]);

  function closeMenu() {
    setMenuOpen(false);
  }

  useEffect(() => {
    const sidebar = sidebarRef.current;
    if (!sidebar) return;
    sidebar.inert = !desktopNav && !menuOpen;
  }, [desktopNav, menuOpen]);

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/login");
  }

  return (
    <div className="admin-shell text-[#1F2937]">
      <header className="admin-mobile-bar">
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-white">Aroll+</p>
          <p className="truncate text-[10px] font-medium uppercase tracking-[0.14em] text-white/55">
            Admin Console
          </p>
        </div>
        <button
          type="button"
          className="inline-flex h-11 w-11 items-center justify-center rounded-xl text-white hover:bg-white/10"
          aria-label={menuOpen ? "Close menu" : "Open menu"}
          aria-expanded={menuOpen}
          aria-controls="admin-navigation"
          onClick={() => setMenuOpen((open) => !open)}
        >
          {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </header>
      {menuOpen && !desktopNav ? (
        <button
          type="button"
          className="admin-nav-backdrop"
          aria-label="Close menu"
          onClick={closeMenu}
        />
      ) : null}
      <aside
        id="admin-navigation"
        className={cn("admin-sidebar", menuOpen && "admin-sidebar-open")}
        ref={sidebarRef}
      >
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
          <button
            type="button"
            className="admin-drawer-close"
            aria-label="Close menu"
            onClick={closeMenu}
          >
            <X className="h-5 w-5" />
          </button>
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
                onClick={closeMenu}
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
              onClick={closeMenu}
            >
              <UserRound strokeWidth={2} />
              <span className="admin-nav-item-label">{profileNav.label}</span>
            </NavLink>
          )}
          <button
            className="admin-nav-item"
            onClick={() => {
              closeMenu();
              setSignOutOpen(true);
            }}
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
