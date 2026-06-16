import { useQuery } from "@tanstack/react-query";
import { useEffect } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { getMe } from "@/lib/api";

function readMustChangePassword(): boolean {
  return localStorage.getItem("aroll_must_change_password") === "true";
}

export function RequireOwnerAuth({
  children,
  passwordChangeOnly = false,
}: {
  children: React.ReactNode;
  passwordChangeOnly?: boolean;
}) {
  const token = localStorage.getItem("aroll_token");
  const { pathname } = useLocation();

  const { data: me, isLoading } = useQuery({
    queryKey: ["me"],
    queryFn: getMe,
    enabled: !!token,
    retry: false,
  });

  useEffect(() => {
    if (!me) return;
    localStorage.setItem(
      "aroll_must_change_password",
      String(me.must_change_password)
    );
    if (me.business_code) {
      localStorage.setItem("aroll_business_code", me.business_code);
    }
  }, [me]);

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

  const mustChange = me?.must_change_password ?? readMustChangePassword();

  if (passwordChangeOnly) {
    if (!mustChange) {
      return <Navigate to="/owner/dashboard" replace />;
    }
    return <>{children}</>;
  }

  if (mustChange) {
    return <Navigate to="/owner/change-password" replace />;
  }

  const setupExempt =
    pathname.startsWith("/owner/setup-wizard") ||
    pathname === "/owner/change-password";

  if (!setupExempt && me && !me.setup_completed_at) {
    return <Navigate to="/owner/setup-wizard" replace />;
  }

  return <>{children}</>;
}
