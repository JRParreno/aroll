import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function AdminProfilePage() {
  return (
    <div className="p-6">
      <Card>
        <CardHeader>
          <CardTitle>Admin Profile</CardTitle>
        </CardHeader>

        <CardContent className="space-y-4">
          <div>
            <p className="text-sm text-muted-foreground">Full Name</p>
            <p className="font-medium">System Administrator</p>
          </div>

          <div>
            <p className="text-sm text-muted-foreground">Email</p>
            <p className="font-medium">admin@arollplus.com</p>
          </div>

          <div>
            <p className="text-sm text-muted-foreground">Role</p>
            <p className="font-medium">Super Admin</p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}