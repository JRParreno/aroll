
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { approveRegistration, listRegistrations } from "@/lib/api";

export function AdminRegistrationsPage() {
  const qc = useQueryClient();
  const { data = [], isLoading } = useQuery({
    queryKey: ["registrations"],
    queryFn: () => listRegistrations("pending"),
  });

  const approve = useMutation({
    mutationFn: (id: string) => approveRegistration(id),
    onSuccess: (res: { business_code: string }) => {
      toast.success(`Approved. Business ID: ${res.business_code}`);
      qc.invalidateQueries({ queryKey: ["registrations"] });
    },
    onError: () => toast.error("Approval failed"),
  });

  return (
    <div className="p-6">
      <Card>
        <CardHeader>
          <CardTitle>Pending business registrations</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {isLoading && <p>Loading…</p>}
          {!isLoading && data.length === 0 && (
            <p className="text-muted-foreground">No pending registrations.</p>
          )}
          {data.map((r) => (
            <div
              key={r.id}
              className="flex flex-wrap items-center justify-between gap-2 rounded-md border p-4"
            >
              <div>
                <p className="font-medium">{r.business_name}</p>
                <p className="text-sm text-muted-foreground">
                  {r.owner_name} · {r.owner_email}
                </p>
                <Badge variant="secondary" className="mt-1">
                  {r.status}
                </Badge>
              </div>
              <Button
                size="sm"
                onClick={() => approve.mutate(r.id)}
                disabled={approve.isPending}
              >
                Approve
              </Button>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
