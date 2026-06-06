import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { approveRegistration, rejectRegistration, listRegistrations, } from "@/lib/api";

export function AdminRegistrationsPage() {
  const qc = useQueryClient();

  const { data = [], isLoading } = useQuery({
    queryKey: ["registrations"],
    queryFn: () => listRegistrations("pending"),
  });

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [open, setOpen] = useState(false);

  const closeRejectDialog = () => {
    setOpen(false);
    setSelectedId(null);
    setReason("");
  };

  const approve = useMutation({
    mutationFn: (id: string) => approveRegistration(id),
    onSuccess: (res: { business_code: string }) => {
      toast.success(`Approved. Business Code: ${res.business_code}`);
      qc.invalidateQueries({ queryKey: ["registrations"] });
    },
    onError: () => {
      toast.error("Approval failed");
    },
  });

  const reject = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      rejectRegistration(id, reason),
    onSuccess: () => {
      toast.success("Registration rejected");
      qc.invalidateQueries({ queryKey: ["registrations"] });
      closeRejectDialog();
    },
    onError: () => {
      toast.error("Rejection failed");
    },
  });

  const handleConfirmReject = () => {
    if (!selectedId || !reason.trim()) {
      toast.error("Please enter a reason");
      return;
    }

    reject.mutate({ id: selectedId, reason: reason.trim() });
  };

  return (
    <div className="p-6">
      <Card>
        <CardHeader>
          <CardTitle>Pending Business Registrations</CardTitle>
        </CardHeader>

        <CardContent className="space-y-4">
          {isLoading && (
            <p className="text-muted-foreground">Loading registrations...</p>
          )}

          {!isLoading && data.length === 0 && (
            <p className="text-muted-foreground">No pending registrations.</p>
          )}

          {data.map((r) => (
            <div
              key={r.id}
              className="flex flex-wrap items-center justify-between gap-4 rounded-md border p-4"
            >
              <div>
                <p className="font-medium">{r.business_name}</p>
                <p className="text-sm text-muted-foreground">
                  {r.owner_name} · {r.owner_email}
                </p>
                <Badge variant="secondary" className="mt-2">
                  {r.status}
                </Badge>
              </div>

              <div className="flex gap-2">
                <Button
                  size="sm"
                  onClick={() => approve.mutate(r.id)}
                  disabled={approve.isPending || reject.isPending}
                >
                  Approve
                </Button>

                <Button
                  size="sm"
                  variant="destructive"
                  onClick={() => {
                    setSelectedId(r.id);
                    setReason("");
                    setOpen(true);
                  }}
                  disabled={approve.isPending || reject.isPending}
                >
                  Reject
                </Button>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      <Dialog
        open={open}
        onOpenChange={(isOpen) => {
          if (!isOpen) closeRejectDialog();
          else setOpen(true);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject Registration</DialogTitle>
          </DialogHeader>

          <Input
            placeholder="Enter rejection reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />

          <DialogFooter>
            <Button variant="outline" onClick={closeRejectDialog}>
              Cancel
            </Button>

            <Button
              variant="destructive"
              onClick={handleConfirmReject}
              disabled={reject.isPending}
            >
              Confirm Reject
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
