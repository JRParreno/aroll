import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Copy } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  createEmployee,
  deactivateEmployee,
  listEmployees,
  listPositions,
  reactivateEmployee,
  updateEmployee,
  type Employee,
} from "@/lib/api";

function statusLabel(status: Employee["status"]) {
  switch (status) {
    case "invited":
      return "Invited";
    case "active":
      return "Active";
    case "inactive":
      return "Inactive";
  }
}

function TemporaryPasswordCell({ employee }: { employee: Employee }) {
  const [copied, setCopied] = useState(false);

  if (employee.must_change_password && employee.temporary_password) {
    async function handleCopy() {
      try {
        await navigator.clipboard.writeText(employee.temporary_password!);
        setCopied(true);
        toast.success("Temporary password copied");
        window.setTimeout(() => setCopied(false), 2000);
      } catch {
        toast.error("Failed to copy temporary password");
      }
    }

    return (
      <div className="flex items-center gap-2">
        <span className="font-mono">{employee.temporary_password}</span>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={handleCopy}
          className="shrink-0"
        >
          {copied ? (
            <Check className="h-4 w-4" />
          ) : (
            <Copy className="h-4 w-4" />
          )}
          <span className="sr-only">Copy temporary password</span>
        </Button>
      </div>
    );
  }

  if (!employee.must_change_password && employee.status === "active") {
    return (
      <span className="text-muted-foreground">
        Password already changed by employee
      </span>
    );
  }

  return <span className="text-muted-foreground">Hidden</span>;
}

export function OwnerEmployeesPage() {
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [positionTitle, setPositionTitle] = useState("");
  const [positionId, setPositionId] = useState("");
  const [phone, setPhone] = useState("");
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  const [editFullName, setEditFullName] = useState("");
  const [editPositionTitle, setEditPositionTitle] = useState("");
  const [editPhone, setEditPhone] = useState("");

  const { data = [], isLoading } = useQuery({
    queryKey: ["employees", "all"],
    queryFn: () => listEmployees(true),
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
        position_title: positionTitle,
        position_id: positionId || undefined,
        employment_type: "full_time",
        phone: phone.trim() || undefined,
      }),
    onSuccess: () => {
      toast.success("Employee created successfully");
      setEmail("");
      setFullName("");
      setPositionTitle("");
      setPositionId("");
      setPhone("");
      setShowForm(false);
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to create employee"),
  });

  const update = useMutation({
    mutationFn: () => {
      if (!editingEmployee) throw new Error("No employee selected");
      return updateEmployee(editingEmployee.id, {
        full_name: editFullName,
        position_title: editPositionTitle,
        phone: editPhone.trim() || null,
      });
    },
    onSuccess: () => {
      toast.success("Employee updated");
      setEditingEmployee(null);
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to update employee"),
  });

  const deactivate = useMutation({
    mutationFn: deactivateEmployee,
    onSuccess: () => {
      toast.success("Employee deactivated");
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to deactivate employee"),
  });

  const reactivate = useMutation({
    mutationFn: reactivateEmployee,
    onSuccess: () => {
      toast.success("Employee reactivated");
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to reactivate employee"),
  });

  function openEdit(employee: Employee) {
    setEditingEmployee(employee);
    setEditFullName(employee.full_name);
    setEditPositionTitle(employee.position_title ?? "");
    setEditPhone(employee.phone ?? "");
  }

  function handlePositionSelect(nextPositionId: string) {
    setPositionId(nextPositionId);
    const selected = positions.find((position) => position.id === nextPositionId);
    if (selected) {
      setPositionTitle(selected.title);
    }
  }

  return (
    <div className="min-h-full space-y-6 bg-muted/30 p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Employees</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Enroll employees, generate login credentials, and manage access for
            your business.
          </p>
        </div>
        <Button onClick={() => setShowForm(!showForm)}>
          {showForm ? "Cancel" : "Add employee"}
        </Button>
      </div>

      {showForm && (
        <Card>
          <CardHeader>
            <CardTitle>New employee</CardTitle>
          </CardHeader>
          <CardContent className="max-w-md space-y-4">
            <div className="space-y-2">
              <Label htmlFor="full-name">Full name</Label>
              <Input
                id="full-name"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Juan Dela Cruz"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="employee@gmail.com"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="position">Position</Label>
              {positions.length > 0 ? (
                <select
                  id="position"
                  className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                  value={positionId}
                  onChange={(e) => handlePositionSelect(e.target.value)}
                >
                  <option value="">Select position</option>
                  {positions.map((position) => (
                    <option key={position.id} value={position.id}>
                      {position.title} — ₱{position.daily_rate}/day
                    </option>
                  ))}
                </select>
              ) : (
                <Input
                  id="position"
                  value={positionTitle}
                  onChange={(e) => setPositionTitle(e.target.value)}
                  placeholder="Cashier"
                />
              )}
              {positions.length > 0 && (
                <Input
                  value={positionTitle}
                  onChange={(e) => setPositionTitle(e.target.value)}
                  placeholder="Or enter position manually"
                />
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="phone">Phone number (optional)</Label>
              <Input
                id="phone"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+63 912 345 6789"
              />
            </div>
            <Button
              onClick={() => create.mutate()}
              disabled={
                create.isPending || !fullName || !email || !positionTitle
              }
            >
              Create & generate password
            </Button>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Enrolled employees</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading && (
            <p className="text-sm text-muted-foreground">Loading employees…</p>
          )}
          {!isLoading && data.length === 0 && (
            <p className="text-sm text-muted-foreground">
              No employees yet. Add your first employee to generate login
              credentials.
            </p>
          )}
          {!isLoading && data.length > 0 && (
            <div className="overflow-x-auto rounded-md border">
              <table className="w-full min-w-[880px] text-sm">
                <thead className="bg-muted/50 text-left">
                  <tr>
                    <th className="px-3 py-2 font-medium">Full name</th>
                    <th className="px-3 py-2 font-medium">Email</th>
                    <th className="px-3 py-2 font-medium">Position</th>
                    <th className="px-3 py-2 font-medium">Temporary password</th>
                    <th className="px-3 py-2 font-medium">Status</th>
                    <th className="px-3 py-2 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {data.map((employee) => (
                    <tr key={employee.id} className="border-t align-middle">
                      <td className="px-3 py-2 font-medium">
                        {employee.full_name}
                      </td>
                      <td className="px-3 py-2 text-muted-foreground">
                        {employee.email}
                      </td>
                      <td className="px-3 py-2">
                        {employee.position_title ?? "—"}
                      </td>
                      <td className="px-3 py-2">
                        <TemporaryPasswordCell employee={employee} />
                      </td>
                      <td className="px-3 py-2">
                        <Badge
                          variant={
                            employee.status === "active"
                              ? "default"
                              : "secondary"
                          }
                        >
                          {statusLabel(employee.status)}
                        </Badge>
                      </td>
                      <td className="px-3 py-2">
                        <div className="flex flex-wrap gap-2">
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => openEdit(employee)}
                          >
                            Edit
                          </Button>
                          {employee.status !== "inactive" ? (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => deactivate.mutate(employee.id)}
                              disabled={deactivate.isPending}
                            >
                              Deactivate
                            </Button>
                          ) : (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => reactivate.mutate(employee.id)}
                              disabled={reactivate.isPending}
                            >
                              Reactivate
                            </Button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog
        open={Boolean(editingEmployee)}
        onOpenChange={(open) => {
          if (!open) setEditingEmployee(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit employee</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="edit-full-name">Full name</Label>
              <Input
                id="edit-full-name"
                value={editFullName}
                onChange={(e) => setEditFullName(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-email">Email</Label>
              <Input
                id="edit-email"
                value={editingEmployee?.email ?? ""}
                disabled
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-position">Position</Label>
              <Input
                id="edit-position"
                value={editPositionTitle}
                onChange={(e) => setEditPositionTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-phone">Phone number</Label>
              <Input
                id="edit-phone"
                value={editPhone}
                onChange={(e) => setEditPhone(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditingEmployee(null)}>
              Cancel
            </Button>
            <Button
              onClick={() => update.mutate()}
              disabled={
                update.isPending || !editFullName || !editPositionTitle
              }
            >
              Save changes
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
