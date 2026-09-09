import { useQuery } from "@tanstack/react-query";
import { Navigate } from "react-router-dom";
import { Mail, ShieldCheck, UserRound } from "lucide-react";
import {
  AdminCard,
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { Badge } from "@/components/ui/badge";
import { getMe } from "@/lib/api";
import { isAdminRole, isOwnerRole, ME_QUERY_KEY } from "@/lib/authSession";

function formatRole(role: string) {
  return role
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function initials(name?: string | null) {
  const parts = (name ?? "Admin")
    .split(" ")
    .map((part) => part.trim())
    .filter(Boolean);

  return parts
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("");
}

export function AdminProfilePage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
    staleTime: 0,
  });

  if (data && isOwnerRole(data.role)) {
    return <Navigate to="/owner/dashboard" replace />;
  }

  return (
    <AdminPage>
      <AdminPageHeader
        eyebrow="Account center"
        title="Admin Profile"
        description="View the currently signed-in platform administrator account."
      />

      <AdminPageContent>
        <AdminCard className="overflow-hidden">
          <div className="border-b border-slate-200/80 bg-gradient-to-r from-[#EAF2FB] to-white px-5 py-8 sm:px-8">
            {isLoading ? (
              <div className="animate-pulse">
                <div className="h-20 w-20 rounded-full bg-white/80" />
                <div className="mt-4 h-5 w-48 rounded bg-white/80" />
                <div className="mt-2 h-4 w-32 rounded bg-white/70" />
              </div>
            ) : data && isAdminRole(data.role) ? (
              <div className="flex flex-col gap-5 sm:flex-row sm:items-center">
                <div className="flex h-24 w-24 items-center justify-center rounded-full border-4 border-white bg-[#1E3A5F] text-2xl font-semibold text-white shadow-sm">
                  {initials(data.full_name)}
                </div>
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="owner-page-title text-[1.5rem] sm:text-[1.75rem]">
                      {data.full_name ?? "Administrator"}
                    </h2>
                    <Badge variant="secondary" className="rounded-full font-medium">
                      {formatRole(data.role)}
                    </Badge>
                  </div>
                  <p className="owner-section-subtitle mt-2 flex items-center gap-2">
                    <ShieldCheck className="h-4 w-4" />
                    Platform administrator
                  </p>
                </div>
              </div>
            ) : null}
          </div>

          <div className="p-5 sm:p-8">
            <h3 className="owner-section-title">Account Information</h3>

            {isLoading && (
              <p className="owner-section-subtitle mt-4">Loading profile...</p>
            )}

            {isError && (
              <p className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                Unable to load profile. Please try again.
              </p>
            )}

            {data && isAdminRole(data.role) && (
              <div className="mt-5 grid gap-4 md:grid-cols-2">
                <ProfileField
                  icon={<UserRound className="h-4 w-4" />}
                  label="Full Name"
                  value={data.full_name ?? "Not set"}
                />
                <ProfileField
                  icon={<Mail className="h-4 w-4" />}
                  label="Email Address"
                  value={data.email}
                />
                <ProfileField
                  icon={<ShieldCheck className="h-4 w-4" />}
                  label="Role"
                  value={formatRole(data.role)}
                />
                <div className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <p className="owner-label uppercase text-[#6B7280]">
                    Account Status
                  </p>
                  <div className="mt-2">
                    {data.must_change_password ? (
                      <Badge variant="secondary" className="rounded-full font-medium">
                        Password change required
                      </Badge>
                    ) : (
                      <Badge className="rounded-full bg-emerald-50 font-medium text-emerald-700 hover:bg-emerald-50">
                        Active
                      </Badge>
                    )}
                  </div>
                </div>
              </div>
            )}
          </div>
        </AdminCard>
      </AdminPageContent>
    </AdminPage>
  );
}

function ProfileField({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
      <p className="owner-label flex items-center gap-2 uppercase text-[#6B7280]">
        {icon}
        {label}
      </p>
      <p className="mt-2 break-words text-[0.9375rem] font-medium text-[#1F2937]">
        {value}
      </p>
    </div>
  );
}
