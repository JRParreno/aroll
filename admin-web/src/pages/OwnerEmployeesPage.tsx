import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  Check,
  Copy,
  Eye,
  EyeOff,
  Filter,
  Phone,
  Plus,
  ScanFace,
  Search,
} from "lucide-react";
import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
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
  deleteEmployee,
  getWeeklySchedule,
  listEmployees,
  listPositions,
  reactivateEmployee,
  updateEmployee,
  type Employee,
} from "@/lib/api";
import { getWeekStart, toDateKey } from "@/components/owner/schedule/scheduleUtils";

type EmployeeForm = {
  fullName: string;
  positionTitle: string;
  positionId: string;
  employmentType: "full_time" | "part_time";
  phone: string;
};

const emptyForm: EmployeeForm = {
  fullName: "",
  positionTitle: "",
  positionId: "",
  employmentType: "full_time",
  phone: "",
};

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

function employmentLabel(value: Employee["employment_type"]) {
  return value === "part_time" ? "Part Timer" : "Full Timer";
}

function EmployeeAvatar({
  employee,
  className = "h-16 w-16 text-base",
}: {
  employee: Pick<Employee, "full_name" | "profile_image_url">;
  className?: string;
}) {
  return (
    <div
      className={`flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-[#d8d8d8] font-extrabold text-[#333] ${className}`}
    >
      {employee.profile_image_url ? (
        <img
          alt={employee.full_name}
          className="h-full w-full object-cover"
          src={employee.profile_image_url}
        />
      ) : (
        initials(employee.full_name)
      )}
    </div>
  );
}

function weekdayLabel(dateKey: string) {
  const date = new Date(`${dateKey}T00:00:00`);
  return date.toLocaleDateString(undefined, { weekday: "short" });
}

export function OwnerEmployeesPage() {
  const qc = useQueryClient();
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [formOpen, setFormOpen] = useState(false);
  const [detailsEmployee, setDetailsEmployee] = useState<Employee | null>(null);
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  const [newCredentials, setNewCredentials] = useState<Employee | null>(null);
  const [employeeToDelete, setEmployeeToDelete] = useState<Employee | null>(null);
  const [showDetailsPassword, setShowDetailsPassword] = useState(false);
  const [copiedField, setCopiedField] = useState<string | null>(null);
  const [form, setForm] = useState<EmployeeForm>(emptyForm);
  const [editForm, setEditForm] = useState<EmployeeForm>(emptyForm);
  const pageSize = 8;
  const weekStartKey = toDateKey(getWeekStart(new Date()));

  const { data: employees = [], isLoading } = useQuery({
    queryKey: ["employees", "all"],
    queryFn: () => listEmployees(true),
    refetchOnWindowFocus: true,
  });

  const { data: positions = [] } = useQuery({
    queryKey: ["positions"],
    queryFn: listPositions,
  });

  const { data: weeklySchedule } = useQuery({
    queryKey: ["weekly-schedule", weekStartKey],
    queryFn: () => getWeeklySchedule(weekStartKey),
  });

  const assignedWorkdays = useMemo(() => {
    const map = new Map<string, Set<string>>();
    for (const assignment of weeklySchedule?.assignments ?? []) {
      const current = map.get(assignment.employee_id) ?? new Set<string>();
      current.add(weekdayLabel(assignment.work_date));
      map.set(assignment.employee_id, current);
    }
    return map;
  }, [weeklySchedule]);

  const filteredEmployees = useMemo(() => {
    const search = query.trim().toLowerCase();
    if (!search) return employees;
    return employees.filter((employee) =>
      [
        employee.full_name,
        employee.phone ?? "",
        employee.position_title ?? "",
        employee.employment_type,
        employee.username,
      ]
        .join(" ")
        .toLowerCase()
        .includes(search)
    );
  }, [employees, query]);

  const totalPages = Math.max(Math.ceil(filteredEmployees.length / pageSize), 1);
  const visibleEmployees = filteredEmployees.slice(
    (page - 1) * pageSize,
    page * pageSize
  );

  function resetForm() {
    setForm(emptyForm);
    setFormOpen(false);
  }

  function pickPosition(nextPositionId: string, target: "create" | "edit") {
    const selected = positions.find((position) => position.id === nextPositionId);
    const update = (current: EmployeeForm) => ({
      ...current,
      positionId: nextPositionId,
      positionTitle: selected?.title ?? "",
    });
    if (target === "create") setForm(update);
    else setEditForm(update);
  }

  const create = useMutation({
    mutationFn: () =>
      createEmployee({
        full_name: form.fullName,
        position_title: form.positionTitle,
        position_id: form.positionId || undefined,
        employment_type: form.employmentType,
        phone: form.phone.trim() || undefined,
      }),
    onSuccess: (employee) => {
      toast.success("Employee added");
      setNewCredentials(employee);
      resetForm();
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to add employee"),
  });

  const update = useMutation({
    mutationFn: () => {
      if (!editingEmployee) throw new Error("No employee selected");
      return updateEmployee(editingEmployee.id, {
        full_name: editForm.fullName,
        position_title: editForm.positionTitle,
        position_id: editForm.positionId || undefined,
        employment_type: editForm.employmentType,
        phone: editForm.phone.trim() || null,
      });
    },
    onSuccess: () => {
      toast.success("Employee updated");
      setEditingEmployee(null);
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to update employee"),
  });

  const remove = useMutation({
    mutationFn: deleteEmployee,
    onSuccess: () => {
      toast.success("Employee deleted successfully.");
      if (employeeToDelete) {
        qc.setQueriesData<Employee[]>({ queryKey: ["employees"] }, (current) =>
          current?.filter((employee) => employee.id !== employeeToDelete.id) ?? current
        );
      }
      setEmployeeToDelete(null);
      setDetailsEmployee(null);
      qc.invalidateQueries({ queryKey: ["employees"] });
      qc.invalidateQueries({ queryKey: ["weekly-schedule"] });
      qc.invalidateQueries({ queryKey: ["owner-attendance-report"] });
      qc.invalidateQueries({ queryKey: ["owner-payroll-report"] });
      qc.invalidateQueries({ queryKey: ["owner-performance"] });
    },
    onError: (error: unknown) => {
      const detail =
        typeof error === "object" &&
        error !== null &&
        "response" in error &&
        typeof error.response === "object" &&
        error.response !== null &&
        "data" in error.response &&
        typeof error.response.data === "object" &&
        error.response.data !== null &&
        "detail" in error.response.data
          ? String(error.response.data.detail)
          : "Failed to delete employee. Please try again.";
      toast.error(detail);
    },
  });

  const restore = useMutation({
    mutationFn: reactivateEmployee,
    onSuccess: () => {
      toast.success("Employee restored");
      setDetailsEmployee(null);
      qc.invalidateQueries({ queryKey: ["employees"] });
    },
    onError: () => toast.error("Failed to restore employee"),
  });

  function openEdit(employee: Employee) {
    setEditingEmployee(employee);
    setEditForm({
      fullName: employee.full_name,
      positionTitle: employee.position_title ?? "",
      positionId: "",
      employmentType: employee.employment_type,
      phone: employee.phone ?? "",
    });
  }

  async function copyCredential(value: string, message: string, field: string) {
    try {
      await navigator.clipboard.writeText(value);
      setCopiedField(field);
      toast.success(message);
      window.setTimeout(() => setCopiedField(null), 1600);
    } catch {
      toast.error("Unable to copy credential");
    }
  }

  const createReady = form.fullName.trim() && form.positionTitle.trim();
  const editReady = editForm.fullName.trim() && editForm.positionTitle.trim();

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Employees"
        actions={
          <Button
            className="h-9 rounded-xl bg-[#1E3A5F] px-3 font-medium text-white hover:bg-[#284B73]"
            onClick={() => setFormOpen(true)}
          >
            <Plus className="h-4 w-4" />
            Add Employee
          </Button>
        }
      />

      <OwnerPageContent>
        <div className="mb-8 flex h-12 items-center gap-4 rounded-2xl border border-slate-200 bg-white px-4 shadow-sm">
          <Search className="h-5 w-5 shrink-0 text-[#777]" />
          <input
            className="h-full flex-1 bg-transparent text-sm outline-none"
            placeholder="Search employees..."
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(1);
            }}
          />
          <Filter className="h-5 w-5 text-[#777]" />
        </div>

        {isLoading ? (
          <p className="text-sm text-muted-foreground">Loading employees...</p>
        ) : visibleEmployees.length === 0 ? (
          <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-muted-foreground shadow-sm">
            No employees found.
          </div>
        ) : (
          <div className="grid gap-x-12 gap-y-4 xl:grid-cols-2">
            {visibleEmployees.map((employee) => {
              const workdays = Array.from(
                assignedWorkdays.get(employee.id) ?? []
              ).join(", ");

              return (
                <button
                  className="rounded-2xl border border-slate-200 bg-white text-left shadow-sm transition hover:shadow-md"
                  key={employee.id}
                  onClick={() => setDetailsEmployee(employee)}
                  type="button"
                >
                  <div className="flex gap-3 px-3 pt-3">
                    <EmployeeAvatar employee={employee} />
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate text-sm font-semibold text-[#1F2937]">
                        {employee.full_name}
                      </h2>
                      <div className="mt-2 flex items-center gap-2 text-[11px] font-semibold text-[#4f4f4f]">
                        <Phone className="h-4 w-4" />
                        {employee.phone || "No contact number"}
                      </div>
                      <div className="mt-1 flex items-center gap-2 text-[11px] font-semibold text-[#4f4f4f]">
                        <BriefcaseBusiness className="h-4 w-4" />
                        {workdays || "No assigned workdays this week"}
                      </div>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center justify-between border-t px-3 py-1.5">
                    <span className="text-[10px] font-semibold text-[#5e5e5e]">
                      {employee.position_title ?? "No role"}
                    </span>
                    <Badge
                      className={
                        employee.employment_type === "full_time"
                          ? "bg-[#b7fa84] text-black hover:bg-[#b7fa84]"
                          : "bg-[#ffe27c] text-black hover:bg-[#ffe27c]"
                      }
                    >
                      {employmentLabel(employee.employment_type)}
                    </Badge>
                  </div>
                </button>
              );
            })}
          </div>
        )}

        <div className="mt-6 flex items-center justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            onClick={() => setPage((current) => Math.max(current - 1, 1))}
          >
            Previous
          </Button>
          <span className="text-sm text-muted-foreground">
            Page {page} of {totalPages}
          </span>
          <Button
            variant="outline"
            size="sm"
            disabled={page >= totalPages}
            onClick={() =>
              setPage((current) => Math.min(current + 1, totalPages))
            }
          >
            Next
          </Button>
        </div>
      </OwnerPageContent>

      <Dialog open={formOpen} onOpenChange={setFormOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add Employee</DialogTitle>
          </DialogHeader>
          <EmployeeFields
            form={form}
            positions={positions}
            onChange={setForm}
            onPositionChange={(id) => pickPosition(id, "create")}
          />
          <DialogFooter>
            <Button variant="outline" onClick={resetForm}>
              Cancel
            </Button>
            <Button
              onClick={() => create.mutate()}
              disabled={!createReady || create.isPending}
            >
              Add Employee
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(editingEmployee)}
        onOpenChange={(open) => {
          if (!open) setEditingEmployee(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Employee</DialogTitle>
          </DialogHeader>
          <EmployeeFields
            editing
            form={editForm}
            positions={positions}
            onChange={setEditForm}
            onPositionChange={(id) => pickPosition(id, "edit")}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditingEmployee(null)}>
              Cancel
            </Button>
            <Button
              onClick={() => update.mutate()}
              disabled={!editReady || update.isPending}
            >
              Save Changes
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(detailsEmployee)}
        onOpenChange={(open) => {
          if (!open) setDetailsEmployee(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Employee Details</DialogTitle>
          </DialogHeader>
          {detailsEmployee && (
            <div className="space-y-3 text-sm">
              <div className="flex items-center gap-3 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-3">
                <EmployeeAvatar
                  employee={detailsEmployee}
                  className="h-16 w-16 text-base"
                />
                <div className="min-w-0">
                  <p className="truncate text-base font-semibold text-[#1F2937]">
                    {detailsEmployee.full_name}
                  </p>
                  <p className="text-xs text-[#6B7280]">
                    {detailsEmployee.position_title ?? "No role"}
                  </p>
                </div>
              </div>
              <p>
                <span className="font-semibold">Name:</span>{" "}
                {detailsEmployee.full_name}
              </p>
              <p>
                <span className="font-semibold">Username:</span>{" "}
                {detailsEmployee.username}
              </p>
              <p>
                <span className="font-semibold">Contact:</span>{" "}
                {detailsEmployee.phone || "No contact number"}
              </p>
              <p>
                <span className="font-semibold">Role:</span>{" "}
                {detailsEmployee.position_title ?? "No role"}
              </p>
              <p>
                <span className="font-semibold">Employment:</span>{" "}
                {employmentLabel(detailsEmployee.employment_type)}
              </p>
              <p>
                <span className="font-semibold">Status:</span>{" "}
                {detailsEmployee.status}
              </p>

              <div className="pt-3">
                <h3 className="mb-3 text-sm font-semibold text-[#1F2937]">
                  Login Credentials
                </h3>
                <div className="space-y-3 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
                  <CredentialRow
                    label="Username"
                    value={detailsEmployee.username}
                    onCopy={() =>
                      copyCredential(
                        detailsEmployee.username,
                        "Username copied",
                        "username"
                      )
                    }
                    copied={copiedField === "username"}
                  />
                  <CredentialRow
                    label="Temporary Password"
                    value={
                      detailsEmployee.temporary_password
                        ? showDetailsPassword
                          ? detailsEmployee.temporary_password
                          : "********"
                        : "Not available"
                    }
                    disabled={!detailsEmployee.temporary_password}
                    onCopy={() => {
                      if (!detailsEmployee.temporary_password) return;
                      copyCredential(
                        detailsEmployee.temporary_password,
                        "Password copied",
                        "password"
                      );
                    }}
                    copied={copiedField === "password"}
                    trailing={
                      detailsEmployee.temporary_password ? (
                        <button
                          className="rounded-lg p-1.5 text-[#6B7280] transition hover:bg-white hover:text-[#1F2937]"
                          onClick={() =>
                            setShowDetailsPassword((current) => !current)
                          }
                          type="button"
                        >
                          {showDetailsPassword ? (
                            <EyeOff className="h-4 w-4" />
                          ) : (
                            <Eye className="h-4 w-4" />
                          )}
                        </button>
                      ) : null
                    }
                  />
                  <div>
                    <p className="text-xs font-medium text-[#6B7280]">
                      Account Status
                    </p>
                    <p className="mt-1 text-sm font-medium text-[#1F2937]">
                      {detailsEmployee.status === "inactive"
                        ? "Disabled"
                        : detailsEmployee.must_change_password
                          ? "Pending Activation"
                          : "Active"}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          )}
          <DialogFooter>
            {detailsEmployee && (
              <>
                <Button
                  variant="outline"
                  onClick={() => {
                    openEdit(detailsEmployee);
                    setDetailsEmployee(null);
                  }}
                >
                  Edit
                </Button>
                <Button variant="outline" asChild>
                  <Link
                    to={`/owner/face-demo?employeeId=${detailsEmployee.id}`}
                    onClick={() => setDetailsEmployee(null)}
                  >
                    <ScanFace className="mr-2 h-4 w-4" />
                    Enroll face
                  </Link>
                </Button>
                {detailsEmployee.status === "inactive" ? (
                  <Button
                    onClick={() => restore.mutate(detailsEmployee.id)}
                    disabled={restore.isPending}
                  >
                    Restore
                  </Button>
                ) : (
                  <Button
                    variant="destructive"
                    onClick={() => setEmployeeToDelete(detailsEmployee)}
                    disabled={remove.isPending}
                  >
                    Delete
                  </Button>
                )}
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(employeeToDelete)}
        onOpenChange={(open) => {
          if (!open && !remove.isPending) setEmployeeToDelete(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Employee</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-[#6B7280]">
            Are you sure you want to delete this employee? This action cannot be
            undone.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setEmployeeToDelete(null)}
              disabled={remove.isPending}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={() => {
                if (employeeToDelete) remove.mutate(employeeToDelete.id);
              }}
              disabled={remove.isPending}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(newCredentials)}
        onOpenChange={(open) => {
          if (!open) setNewCredentials(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Employee Login Credentials</DialogTitle>
          </DialogHeader>
          {newCredentials && (
            <div className="space-y-4 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4 text-sm">
              <p className="text-[#6B7280]">
                Share these credentials with the employee so they can activate
                their account.
              </p>
              <div>
                <p className="text-xs font-medium text-[#6B7280]">Username</p>
                <p className="mt-1 rounded-lg bg-white px-3 py-2 font-mono text-[#1F2937]">
                  {newCredentials.generated_username ?? newCredentials.username}
                </p>
              </div>
              <div>
                <p className="text-xs font-medium text-[#6B7280]">
                  Temporary Password
                </p>
                <p className="mt-1 rounded-lg bg-white px-3 py-2 font-mono text-[#1F2937]">
                  {newCredentials.temporary_password ?? "Hidden"}
                </p>
              </div>
            </div>
          )}
          <DialogFooter>
            <Button onClick={() => setNewCredentials(null)}>Done</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}

function CredentialRow({
  label,
  value,
  onCopy,
  copied,
  trailing,
  disabled = false,
}: {
  label: string;
  value: string;
  onCopy: () => void;
  copied: boolean;
  trailing?: React.ReactNode;
  disabled?: boolean;
}) {
  return (
    <div>
      <p className="text-xs font-medium text-[#6B7280]">{label}</p>
      <div className="mt-1 flex items-center gap-2 rounded-xl bg-white px-3 py-2">
        <span className="min-w-0 flex-1 truncate font-mono text-sm text-[#1F2937]">
          {value}
        </span>
        {trailing}
        <button
          className="rounded-lg p-1.5 text-[#6B7280] transition hover:bg-[#F3F6FA] hover:text-[#1F2937] disabled:cursor-not-allowed disabled:opacity-40"
          disabled={disabled}
          onClick={onCopy}
          type="button"
        >
          {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
        </button>
      </div>
    </div>
  );
}

function EmployeeFields({
  form,
  positions,
  editing = false,
  onChange,
  onPositionChange,
}: {
  form: EmployeeForm;
  positions: { id: string; title: string; daily_rate: number }[];
  editing?: boolean;
  onChange: (form: EmployeeForm) => void;
  onPositionChange: (positionId: string) => void;
}) {
  return (
    <div className="space-y-4">
      {!editing && (
        <p className="rounded-xl border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-800">
          Username and temporary password are generated automatically after
          enrollment.
        </p>
      )}
      <div className="space-y-2">
        <Label htmlFor="employee-name">Full Name</Label>
        <Input
          id="employee-name"
          value={form.fullName}
          onChange={(event) =>
            onChange({ ...form, fullName: event.target.value })
          }
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="employee-phone">Contact Number</Label>
        <Input
          id="employee-phone"
          value={form.phone}
          onChange={(event) =>
            onChange({ ...form, phone: event.target.value })
          }
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="employee-position">Position/Role</Label>
        {positions.length > 0 ? (
          <select
            id="employee-position"
            className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            value={form.positionId}
            onChange={(event) => onPositionChange(event.target.value)}
          >
            <option value="">Select position</option>
            {positions.map((position) => (
              <option key={position.id} value={position.id}>
                {position.title}
              </option>
            ))}
          </select>
        ) : (
          <Input
            id="employee-position"
            value={form.positionTitle}
            onChange={(event) =>
              onChange({ ...form, positionTitle: event.target.value })
            }
          />
        )}
      </div>
      <div className="space-y-2">
        <Label htmlFor="employee-type">Employment Type</Label>
        <select
          id="employee-type"
          className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
          value={form.employmentType}
          onChange={(event) =>
            onChange({
              ...form,
              employmentType: event.target.value as EmployeeForm["employmentType"],
            })
          }
        >
          <option value="full_time">Full-Time</option>
          <option value="part_time">Part-Time</option>
        </select>
      </div>
    </div>
  );
}
