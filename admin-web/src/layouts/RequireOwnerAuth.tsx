import { useQuery } from "@tanstack/react-query";
import { Navigate, useLocation } from "react-router-dom";
import { getMe } from "@/lib/api";
import {
  clearAuthSession,
  getAuthToken,
  isAdminRole,
  isOwnerRole,
  ME_QUERY_KEY,
} from "@/lib/authSession";

export function RequireOwnerAuth({
  children,
  passwordChangeOnly = false,
}: {
  children: React.ReactNode;
  passwordChangeOnly?: boolean;
}) {
  const token = getAuthToken();
  const { pathname } = useLocation();

  const { data: me, isLoading, isError } = useQuery({
    queryKey: ME_QUERY_KEY,
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
    clearAuthSession();
    return <Navigate to="/owner-login" replace />;
  }

  if (isAdminRole(me.role)) {
    return <Navigate to="/admin/dashboard" replace />;
  }

  if (!isOwnerRole(me.role)) {
    clearAuthSession();
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
    pathname === "/owner/change-password" ||
    pathname === "/owner/location";

  if (!setupExempt && !me.setup_completed_at) {
    return <Navigate to="/owner/setup-wizard" replace />;
  }

  return <>{children}</>;
}
