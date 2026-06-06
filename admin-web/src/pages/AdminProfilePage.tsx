import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getMe } from "@/lib/api";

function formatRole(role: string) {
  return role
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

export function AdminProfilePage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["me"],
    queryFn: getMe,
  });

  return (
    <div className="p-6">
      <Card>
        <CardHeader>
          <CardTitle>Admin Profile</CardTitle>
        </CardHeader>

        <CardContent className="space-y-4">
          {isLoading && (
            <p className="text-muted-foreground">Loading profile...</p>
          )}

          {isError && (
            <p className="text-muted-foreground">
              Unable to load profile. Please try again.
            </p>
          )}

          {data && (
            <>
              <div>
                <p className="text-sm text-muted-foreground">Full Name</p>
                <p className="font-medium">{data.full_name ?? "—"}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground">Email</p>
                <p className="font-medium">{data.email}</p>
              </div>

              <div>
                <p className="text-sm text-muted-foreground">Role</p>
                <p className="font-medium">{formatRole(data.role)}</p>
              </div>

              {data.business_name && (
                <div>
                  <p className="text-sm text-muted-foreground">Business</p>
                  <p className="font-medium">{data.business_name}</p>
                </div>
              )}

              {data.must_change_password && (
                <Badge variant="secondary">Password change required</Badge>
              )}
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
