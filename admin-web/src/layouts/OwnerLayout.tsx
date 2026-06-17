import { useQuery, useQueryClient } from "@tanstack/react-query";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { getMe } from "@/lib/api";
import { clearAuthSession, ME_QUERY_KEY } from "@/lib/authSession";
import { cn } from "@/lib/utils";
import { ownerNavItems } from "@/layouts/ownerNav";

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

  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });

  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "My Business";
  const businessCode =
    me?.business_code ?? localStorage.getItem("aroll_business_code") ?? "—";

  function logout() {
    clearAuthSession();
    qc.clear();
    navigate("/owner-login");
  }

  return (
    <div className="min-h-screen lg:flex">
      <aside className="flex w-full flex-col border-b bg-background p-4 lg:fixed lg:inset-y-0 lg:z-30 lg:w-60 lg:border-b-0 lg:border-r">
        <div className="mb-4 border-b pb-4">
          <p className="font-bold text-lg">Aroll+</p>
          <p className="mt-2 text-sm font-semibold">{businessName}</p>
          <p className="text-xs text-muted-foreground">
            Business Code: {businessCode}
          </p>
        </div>

        <nav className="flex max-h-[50vh] flex-1 flex-col gap-1 overflow-y-auto lg:max-h-none">
          {ownerNavItems.map((item) => {
            const active = isNavItemActive(pathname, item.to, item.activePaths);

            return (
              <NavLink
                key={item.to}
                to={item.to}
                className={cn(
                  "block rounded-md px-3 py-2 text-sm hover:bg-muted",
                  active && "bg-muted font-medium"
                )}
              >
                {item.label}
              </NavLink>
            );
          })}

          <div className="mt-3 border-t pt-3">
            <Button
              variant="outline"
              size="sm"
              className="w-full"
              onClick={logout}
            >
              Log Out
            </Button>
          </div>
        </nav>
      </aside>

      <main className="min-h-screen flex-1 bg-muted/30 lg:pl-60">
        <Outlet />
      </main>
    </div>
  );
}
