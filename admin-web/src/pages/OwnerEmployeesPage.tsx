import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createEmployee, listEmployees } from "@/lib/api";

export function OwnerEmployeesPage() {
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [position, setPosition] = useState("");
  const [tempPassword, setTempPassword] = useState<string | null>(null);

  const { data = [], isLoading } = useQuery({
    queryKey: ["employees"],
    queryFn: listEmployees,
  });

  const create = useMutation({
    mutationFn: () =>
      createEmployee({
        email,
        full_name: fullName,
        position_title: position || undefined,
        employment_type: "full_time",
      }),
    onSuccess: (res) => {
      setTempPassword(res.temporary_password);
      toast.success("Employee created");
      setEmail("");
      setFullName("");
      setPosition("");
      setShowForm(false);
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to create employee"),
  });

  return (
    <div className="min-h-full space-y-6 bg-muted/30 p-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-semibold">Employees</h1>
        <Button onClick={() => setShowForm(!showForm)}>
          {showForm ? "Cancel" : "Add employee"}
        </Button>
      </div>

      {tempPassword && (
        <Card className="border-primary">
          <CardContent className="pt-6">
            <p className="font-medium text-primary">One-time temporary password</p>
            <p className="text-2xl font-mono mt-2">{tempPassword}</p>
            <p className="text-sm text-muted-foreground mt-2">
              Share with the employee. They must change it on first login in the mobile app.
            </p>
            <Button variant="outline" className="mt-4" onClick={() => setTempPassword(null)}>
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
          <CardContent className="space-y-4 max-w-md">
            <div className="space-y-2">
              <Label>Full name</Label>
              <Input value={fullName} onChange={(e) => setFullName(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Email</Label>
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Position</Label>
              <Input value={position} onChange={(e) => setPosition(e.target.value)} />
            </div>
            <Button onClick={() => create.mutate()} disabled={create.isPending}>
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
              <li key={e.id} className="py-3 flex justify-between">
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
