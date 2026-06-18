import { useQuery } from "@tanstack/react-query";
import { Navigate } from "react-router-dom";
import { getMe } from "@/lib/api";
import {
  clearAuthSession,
  getAuthToken,
  isAdminRole,
  isOwnerRole,
  ME_QUERY_KEY,
} from "@/lib/authSession";

export function RequireAdminAuth({ children }: { children: React.ReactNode }) {
  const token = getAuthToken();

  const { data: me, isLoading, isError } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
    enabled: !!token,
    retry: false,
    staleTime: 0,
  });

  if (!token) {
    return <Navigate to="/login" replace />;
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
    return <Navigate to="/login" replace />;
  }

  if (!isAdminRole(me.role)) {
    if (isOwnerRole(me.role)) {
      return <Navigate to="/owner/dashboard" replace />;
    }
    clearAuthSession();
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
}
