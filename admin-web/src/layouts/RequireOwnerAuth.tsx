import { useQuery } from "@tanstack/react-query";
import { Navigate, useLocation } from "react-router-dom";
import { getMe } from "@/lib/api";

export function RequireOwnerAuth({
  children,
  passwordChangeOnly = false,
}: {
  children: React.ReactNode;
  passwordChangeOnly?: boolean;
}) {
  const token = localStorage.getItem("aroll_token");
  const { pathname } = useLocation();

  const { data: me, isLoading, isError } = useQuery({
    queryKey: ["me"],
    queryFn: getMe,
    enabled: !!token,
    retry: false,
    staleTime: 0,
  });

  if (!token) {
    return <Navigate to="/owner-login" replace />;
  }

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center text-muted-foreground">
        Loading…
      </div>
    );
  }

  if (isError || !me) {
    localStorage.removeItem("aroll_token");
    localStorage.removeItem("aroll_must_change_password");
    localStorage.removeItem("aroll_business_code");
    return <Navigate to="/owner-login" replace />;
  }

  if (me.business_code) {
    localStorage.setItem("aroll_business_code", me.business_code);
  }

  const mustChange = me.must_change_password;

  if (passwordChangeOnly) {
    if (!mustChange) {
      return (
        <Navigate
          to={me.setup_completed_at ? "/owner/dashboard" : "/owner/setup-wizard"}
          replace
        />
      );
    }
    return <>{children}</>;
  }

  if (mustChange) {
    return <Navigate to="/owner/change-password" replace />;
  }

  const setupExempt =
    pathname.startsWith("/owner/setup-wizard") ||
    pathname === "/owner/change-password";

  if (!setupExempt && !me.setup_completed_at) {
    return <Navigate to="/owner/setup-wizard" replace />;
  }

  return <>{children}</>;
}
