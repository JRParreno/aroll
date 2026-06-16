import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createEmployee, listEmployees, listPositions } from "@/lib/api";

export function OwnerEmployeesPage() {
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [positionId, setPositionId] = useState("");
  const [tempPassword, setTempPassword] = useState<string | null>(null);

  const { data = [], isLoading } = useQuery({
    queryKey: ["employees"],
    queryFn: listEmployees,
  });

  const { data: positions = [] } = useQuery({
    queryKey: ["positions"],
    queryFn: listPositions,
  });

  const create = useMutation({
    mutationFn: () =>
      createEmployee({
        email,
        full_name: fullName,
        position_id: positionId || undefined,
        employment_type: "full_time",
      }),
    onSuccess: (res) => {
      setTempPassword(res.temporary_password);
      toast.success("Employee created");
      setEmail("");
      setFullName("");
      setPositionId("");
      setShowForm(false);
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to create employee"),
  });

  return (
    <div className="min-h-full space-y-6 bg-muted/30 p-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Employees</h1>
        <Button onClick={() => setShowForm(!showForm)}>
          {showForm ? "Cancel" : "Add employee"}
        </Button>
      </div>

      {tempPassword && (
        <Card className="border-primary">
          <CardContent className="pt-6">
            <p className="font-medium text-primary">One-time temporary password</p>
            <p className="mt-2 font-mono text-2xl">{tempPassword}</p>
            <p className="mt-2 text-sm text-muted-foreground">
              Share with the employee. They must change it on first login in the
              mobile app.
            </p>
            <Button
              variant="outline"
              className="mt-4"
              onClick={() => setTempPassword(null)}
            >
              Dismiss
            </Button>
          </CardContent>
        </Card>
      )}

      {showForm && (
        <Card>
          <CardHeader>
            <CardTitle>New employee</CardTitle>
          </CardHeader>
          <CardContent className="max-w-md space-y-4">
            <div className="space-y-2">
              <Label>Full name</Label>
              <Input
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Email</Label>
              <Input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Position</Label>
              <select
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                value={positionId}
                onChange={(e) => setPositionId(e.target.value)}
              >
                <option value="">Select position</option>
                {positions.map((position) => (
                  <option key={position.id} value={position.id}>
                    {position.title} — ₱{position.daily_rate}/day
                  </option>
                ))}
              </select>
              {positions.length === 0 && (
                <p className="text-xs text-muted-foreground">
                  No positions found. Create positions in Business Setup first.
                </p>
              )}
            </div>
            <Button
              onClick={() => create.mutate()}
              disabled={create.isPending || !fullName || !email}
            >
              Create & generate password
            </Button>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardContent className="pt-6">
          {isLoading && <p>Loading…</p>}
          <ul className="divide-y">
            {data.map((e) => (
              <li key={e.id} className="flex justify-between py-3">
                <div>
                  <p className="font-medium">{e.full_name}</p>
                  <p className="text-sm text-muted-foreground">{e.email}</p>
                </div>
                <span className="text-sm">{e.position_title ?? "—"}</span>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}
