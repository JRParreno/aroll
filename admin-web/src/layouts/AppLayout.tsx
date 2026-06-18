import { Link, Outlet, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { clearAuthSession } from "@/lib/authSession";

type NavItem = { to: string; label: string };

export function AppLayout({ nav }: { nav: NavItem[] }) {
  const navigate = useNavigate();
  const qc = useQueryClient();

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/login");
  }

  return (
    <div className="min-h-screen flex">
      <aside className="w-56 border-r bg-muted/30 p-4 flex flex-col">
        <p className="font-bold text-lg mb-6">Aroll+</p>
        <nav className="flex flex-col gap-2 flex-1">
          {nav.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              className="rounded-md px-3 py-2 text-sm hover:bg-muted"
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <Button variant="outline" size="sm" onClick={logout}>
          Log out
        </Button>
      </aside>
      <main className="flex-1">
        <Outlet />
      </main>
    </div>
  );
}
