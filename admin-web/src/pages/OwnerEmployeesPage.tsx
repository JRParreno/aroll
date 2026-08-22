import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BriefcaseBusiness,
  CalendarDays,
  Check,
  Copy,
  Eye,
  EyeOff,
  Filter,
  IdCard,
  KeyRound,
  Phone,
  Plus,
  ScanFace,
  Search,
  UserPlus,
} from "lucide-react";
import { useMemo, useState, type ReactNode } from "react";
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
  type PayBasis,
} from "@/lib/api";
import { getWeekStart, toDateKey } from "@/components/owner/schedule/scheduleUtils";
import { cn } from "@/lib/utils";

type EmployeeForm = {
  fullName: string;
  positionTitle: string;
  positionId: string;
  employmentType: "full_time" | "part_time";
  phone: string;
  payBasis: PayBasis;
  dailyRate: string;
  hourlyRate: string;
  monthlySalary: string;
};

const emptyForm: EmployeeForm = {
  fullName: "",
  positionTitle: "",
  positionId: "",
  employmentType: "full_time",
  phone: "",
  payBasis: "daily",
  dailyRate: "",
  hourlyRate: "",
  monthlySalary: "",
};

function ratePayload(form: EmployeeForm) {
  const daily =
    form.payBasis === "daily" && form.dailyRate.trim()
      ? Number(form.dailyRate)
      : null;
  const hourly =
    form.payBasis === "hourly" && form.hourlyRate.trim()
      ? Number(form.hourlyRate)
      : null;
  const monthly =
    form.payBasis === "monthly" && form.monthlySalary.trim()
      ? Number(form.monthlySalary)
      : null;
  return {
    pay_basis: form.payBasis,
    daily_rate: daily,
    hourly_rate: hourly,
    monthly_salary: monthly,
  };
}

function formPayReady(form: EmployeeForm) {
  if (form.payBasis === "daily") return Number(form.dailyRate) > 0;
  if (form.payBasis === "hourly") return Number(form.hourlyRate) > 0;
  return Number(form.monthlySalary) > 0;
}

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

function accountStatusLabel(employee: Pick<Employee, "status" | "must_change_password">) {
  if (employee.status === "inactive") return "Disabled";
  if (employee.must_change_password) return "Pending Activation";
  return "Active";
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
      className={cn(
        "flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-[#d8d8d8] font-extrabold text-[#333] ring-2 ring-white shadow-sm",
        className
      )}
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

function DetailInfoRow({
  icon,
  label,
  value,
}: {
  icon: ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-start gap-3 px-1 py-2.5">
      <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-[#EEF3F8] text-[#1F456B]">
        {icon}
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-[#9CA3AF]">
          {label}
        </p>
        <p className="mt-0.5 truncate text-sm font-medium text-[#111827]">{value}</p>
      </div>
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
    if (target === "create") {
      setForm((current) => ({
        ...current,
        positionId: nextPositionId,
        positionTitle: selected?.title ?? "",
        // Prefill Position default; owner may override before save.
        dailyRate:
          current.payBasis === "daily" && selected?.daily_rate != null
            ? String(selected.daily_rate)
            : current.dailyRate,
      }));
      return;
    }
    // Edit: suggest Position default only when daily pay and rate still empty /
    // still matches the previous position default — never silently overwrite.
    setEditForm((current) => {
      const prev = positions.find((p) => p.id === current.positionId);
      const stillDefault =
        current.payBasis === "daily" &&
        (!current.dailyRate.trim() ||
          (prev?.daily_rate != null &&
            Number(current.dailyRate) === Number(prev.daily_rate)));
      return {
        ...current,
        positionId: nextPositionId,
        positionTitle: selected?.title ?? "",
        dailyRate:
          stillDefault && selected?.daily_rate != null
            ? String(selected.daily_rate)
            : current.dailyRate,
      };
    });
  }

  const create = useMutation({
    mutationFn: () =>
      createEmployee({
        full_name: form.fullName,
        position_title: form.positionTitle,
        position_id: form.positionId || undefined,
        employment_type: form.employmentType,
        phone: form.phone.trim() || undefined,
        ...ratePayload(form),
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
        ...ratePayload(editForm),
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
    const matchedPosition =
      positions.find((position) => position.id === (employee.position_id ?? "")) ??
      positions.find(
        (position) => position.title === (employee.position_title ?? "")
      );
    setEditingEmployee(employee);
    setEditForm({
      fullName: employee.full_name,
      positionTitle: employee.position_title ?? "",
      positionId: matchedPosition?.id ?? employee.position_id ?? "",
      employmentType: employee.employment_type as EmployeeForm["employmentType"],
      phone: employee.phone ?? "",
      payBasis: employee.pay_basis ?? "daily",
      dailyRate:
        employee.daily_rate != null ? String(employee.daily_rate) : "",
      hourlyRate:
        employee.hourly_rate != null ? String(employee.hourly_rate) : "",
      monthlySalary:
        employee.monthly_salary != null ? String(employee.monthly_salary) : "",
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

  const createReady =
    form.fullName.trim() && form.positionTitle.trim() && formPayReady(form);
  const editReady =
    editForm.fullName.trim() &&
    editForm.positionTitle.trim() &&
    formPayReady(editForm);

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Employees"
        description="Search your team, open a profile, or enroll a new employee."
        actions={
          <Button
            className="h-9 gap-1.5 rounded-xl px-3 font-medium"
            onClick={() => setFormOpen(true)}
          >
            <Plus className="h-4 w-4" />
            Add Employee
          </Button>
        }
      />

      <OwnerPageContent>
        <div className="owner-card flex h-12 items-center gap-3 px-4">
          <Search className="h-4 w-4 shrink-0 text-[#9CA3AF]" />
          <input
            className="h-full flex-1 bg-transparent text-sm text-[#1F2937] outline-none placeholder:text-[#9CA3AF]"
            placeholder="Search by name, role, phone, or username..."
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(1);
            }}
          />
          <span className="hidden items-center gap-1 rounded-lg bg-[#F3F6FA] px-2 py-1 text-[11px] font-medium text-[#6B7280] sm:inline-flex">
            <Filter className="h-3.5 w-3.5" />
            Search
          </span>
        </div>

        {isLoading ? (
          <p className="text-sm text-[#6B7280]">Loading employees...</p>
        ) : visibleEmployees.length === 0 ? (
          <div className="owner-card p-8 text-center text-sm text-[#6B7280]">
            No employees found.
          </div>
        ) : (
          <div className="grid gap-4 xl:grid-cols-2">
            {visibleEmployees.map((employee) => {
              const workdays = Array.from(
                assignedWorkdays.get(employee.id) ?? []
              ).join(", ");

              return (
                <button
                  className="owner-card group text-left transition hover:-translate-y-0.5 hover:shadow-[0_8px_28px_rgba(15,23,42,0.08)]"
                  key={employee.id}
                  onClick={() => setDetailsEmployee(employee)}
                  type="button"
                >
                  <div className="flex gap-3 px-4 pt-4">
                    <EmployeeAvatar employee={employee} />
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate text-sm font-semibold text-[#1F2937] group-hover:text-[#1E3A5F]">
                        {employee.full_name}
                      </h2>
                      <div className="mt-2 flex items-center gap-2 text-[11px] font-medium text-[#6B7280]">
                        <Phone className="h-3.5 w-3.5 shrink-0 text-[#9CA3AF]" />
                        <span className="truncate">
                          {employee.phone || "No contact number"}
                        </span>
                      </div>
                      <div className="mt-1 flex items-center gap-2 text-[11px] font-medium text-[#6B7280]">
                        <BriefcaseBusiness className="h-3.5 w-3.5 shrink-0 text-[#9CA3AF]" />
                        <span className="truncate">
                          {workdays || "No assigned workdays this week"}
                        </span>
                      </div>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center justify-between border-t border-slate-100 px-4 py-2.5">
                    <span className="truncate text-[11px] font-medium text-[#6B7280]">
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

        <div className="flex items-center justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            className="rounded-xl"
            disabled={page <= 1}
            onClick={() => setPage((current) => Math.max(current - 1, 1))}
          >
            Previous
          </Button>
          <span className="text-sm text-[#6B7280]">
            Page {page} of {totalPages}
          </span>
          <Button
            variant="outline"
            size="sm"
            className="rounded-xl"
            disabled={page >= totalPages}
            onClick={() =>
              setPage((current) => Math.min(current + 1, totalPages))
            }
          >
            Next
          </Button>
        </div>
      </OwnerPageContent>

      <Dialog
        open={formOpen}
        onOpenChange={(open) => {
          if (!open) resetForm();
          else setFormOpen(true);
        }}
      >
        <DialogContent className="max-h-[90vh] gap-0 overflow-y-auto p-0 sm:max-w-lg sm:rounded-2xl">
          <DialogHeader className="border-b border-slate-100 px-6 pb-4 pt-6">
            <DialogTitle className="text-[#111827]">Add Employee</DialogTitle>
          </DialogHeader>
          <div className="space-y-5 px-6 py-5">
            <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#1F456B] to-[#2A5A84] p-4 text-white shadow-sm">
              <div className="pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full bg-white/10" />
              <div className="pointer-events-none absolute -bottom-10 right-10 h-24 w-24 rounded-full bg-[#B9D8EE]/20" />
              <div className="relative flex items-center gap-4">
                <EmployeeAvatar
                  className="h-[72px] w-[72px] text-lg ring-[#B9D8EE]/50"
                  employee={{
                    full_name: form.fullName.trim() || "New Employee",
                    profile_image_url: null,
                  }}
                />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-lg font-semibold tracking-tight">
                    {form.fullName.trim() || "New team member"}
                  </p>
                  <p className="mt-0.5 truncate text-sm text-white/80">
                    {form.positionTitle.trim() || "Choose a role to continue"}
                  </p>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <span
                      className={cn(
                        "rounded-full px-2.5 py-1 text-[11px] font-semibold text-[#111827]",
                        form.employmentType === "full_time"
                          ? "bg-[#b7fa84]"
                          : "bg-[#ffe27c]"
                      )}
                    >
                      {employmentLabel(form.employmentType)}
                    </span>
                    <span className="inline-flex items-center gap-1 rounded-full bg-white/15 px-2.5 py-1 text-[11px] font-semibold text-white">
                      <UserPlus className="h-3.5 w-3.5" />
                      Enrolling
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <div className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4 shadow-sm">
              <EmployeeFields
                form={form}
                positions={positions}
                onChange={setForm}
                onPositionChange={(id) => pickPosition(id, "create")}
              />
            </div>
          </div>
          <DialogFooter className="gap-2 border-t border-slate-100 px-6 py-4 sm:justify-end">
            <Button
              className="rounded-xl"
              variant="outline"
              onClick={resetForm}
            >
              Cancel
            </Button>
            <Button
              className="rounded-xl bg-[#1F456B] hover:bg-[#2A5A84]"
              onClick={() => create.mutate()}
              disabled={!createReady || create.isPending}
            >
              {create.isPending ? "Adding..." : "Add Employee"}
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
        <DialogContent className="max-h-[90vh] gap-0 overflow-y-auto p-0 sm:rounded-2xl">
          <DialogHeader className="border-b border-slate-100 px-6 pb-4 pt-6">
            <DialogTitle className="text-[#111827]">Edit Employee</DialogTitle>
          </DialogHeader>
          {editingEmployee && (
            <div className="space-y-5 px-6 py-5">
              <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#1F456B] to-[#2A5A84] p-4 text-white shadow-sm">
                <div className="pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full bg-white/10" />
                <div className="pointer-events-none absolute -bottom-10 right-10 h-24 w-24 rounded-full bg-[#B9D8EE]/20" />
                <div className="relative flex items-center gap-4">
                  <EmployeeAvatar
                    className="h-[72px] w-[72px] text-lg ring-[#B9D8EE]/50"
                    employee={editingEmployee}
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-lg font-semibold tracking-tight">
                      {editForm.fullName.trim() || editingEmployee.full_name}
                    </p>
                    <p className="mt-0.5 truncate text-sm text-white/80">
                      {editForm.positionTitle.trim() ||
                        editingEmployee.position_title ||
                        "No role"}
                    </p>
                    <div className="mt-3 flex flex-wrap gap-2">
                      <span
                        className={cn(
                          "rounded-full px-2.5 py-1 text-[11px] font-semibold text-[#111827]",
                          editForm.employmentType === "full_time"
                            ? "bg-[#b7fa84]"
                            : "bg-[#ffe27c]"
                        )}
                      >
                        {employmentLabel(editForm.employmentType)}
                      </span>
                      <span className="rounded-full bg-white/15 px-2.5 py-1 text-[11px] font-semibold text-white">
                        Editing profile
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4 shadow-sm">
                <EmployeeFields
                  editing
                  form={editForm}
                  positions={positions}
                  onChange={setEditForm}
                  onPositionChange={(id) => pickPosition(id, "edit")}
                />
              </div>
            </div>
          )}
          <DialogFooter className="gap-2 border-t border-slate-100 px-6 py-4 sm:justify-end">
            <Button
              className="rounded-xl"
              variant="outline"
              onClick={() => setEditingEmployee(null)}
            >
              Cancel
            </Button>
            <Button
              className="rounded-xl bg-[#1F456B] text-white hover:bg-[#17395D]"
              onClick={() => update.mutate()}
              disabled={!editReady || update.isPending}
            >
              {update.isPending ? "Saving…" : "Save Changes"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(detailsEmployee)}
        onOpenChange={(open) => {
          if (!open) {
            setDetailsEmployee(null);
            setShowDetailsPassword(false);
          }
        }}
      >
        <DialogContent className="max-h-[90vh] gap-0 overflow-y-auto p-0 sm:rounded-2xl">
          <DialogHeader className="border-b border-slate-100 px-6 pb-4 pt-6">
            <DialogTitle className="text-[#111827]">Employee Details</DialogTitle>
          </DialogHeader>
          {detailsEmployee && (
            <div className="space-y-5 px-6 py-5">
              {(() => {
                const statusLabel = accountStatusLabel(detailsEmployee);
                const workdays =
                  Array.from(assignedWorkdays.get(detailsEmployee.id) ?? [])
                    .join(", ") || "No assigned workdays this week";

                return (
                  <>
                    <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#1F456B] to-[#2A5A84] p-4 text-white shadow-sm">
                      <div className="pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full bg-white/10" />
                      <div className="pointer-events-none absolute -bottom-10 right-10 h-24 w-24 rounded-full bg-[#B9D8EE]/20" />
                      <div className="relative flex items-center gap-4">
                        <EmployeeAvatar
                          className="h-[72px] w-[72px] text-lg ring-[#B9D8EE]/50"
                          employee={detailsEmployee}
                        />
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-lg font-semibold tracking-tight">
                            {detailsEmployee.full_name}
                          </p>
                          <p className="mt-0.5 truncate text-sm text-white/80">
                            {detailsEmployee.position_title ?? "No role"}
                          </p>
                          <div className="mt-3 flex flex-wrap gap-2">
                            <span
                              className={cn(
                                "rounded-full px-2.5 py-1 text-[11px] font-semibold text-[#111827]",
                                detailsEmployee.employment_type === "full_time"
                                  ? "bg-[#b7fa84]"
                                  : "bg-[#ffe27c]"
                              )}
                            >
                              {employmentLabel(detailsEmployee.employment_type)}
                            </span>
                            <span
                              className={cn(
                                "rounded-full px-2.5 py-1 text-[11px] font-semibold",
                                statusLabel === "Active" &&
                                  "bg-emerald-100 text-emerald-800",
                                statusLabel === "Pending Activation" &&
                                  "bg-amber-100 text-amber-900",
                                statusLabel === "Disabled" &&
                                  "bg-slate-200 text-slate-700"
                              )}
                            >
                              {statusLabel}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="divide-y divide-slate-100 rounded-2xl border border-slate-200 bg-[#FAFBFC] px-3 py-1">
                      <DetailInfoRow
                        icon={<Phone className="h-4 w-4" />}
                        label="Contact"
                        value={detailsEmployee.phone || "No contact number"}
                      />
                      <DetailInfoRow
                        icon={<BriefcaseBusiness className="h-4 w-4" />}
                        label="Role"
                        value={detailsEmployee.position_title ?? "No role"}
                      />
                      <DetailInfoRow
                        icon={<IdCard className="h-4 w-4" />}
                        label="Employment"
                        value={employmentLabel(detailsEmployee.employment_type)}
                      />
                      <DetailInfoRow
                        icon={<CalendarDays className="h-4 w-4" />}
                        label="Work days"
                        value={workdays}
                      />
                      <DetailInfoRow
                        icon={<KeyRound className="h-4 w-4" />}
                        label="Username"
                        value={detailsEmployee.username}
                      />
                    </div>

                    <div>
                      <h3 className="mb-2 text-sm font-semibold text-[#111827]">
                        Login Credentials
                      </h3>
                      <div className="space-y-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
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
                                className="rounded-lg p-1.5 text-[#6B7280] transition hover:bg-[#F3F6FA] hover:text-[#1F2937]"
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
                        <div className="flex items-center justify-between rounded-xl bg-[#F8FAFC] px-3 py-2.5">
                          <p className="text-xs font-medium text-[#6B7280]">
                            Account Status
                          </p>
                          <span
                            className={cn(
                              "rounded-full px-2.5 py-1 text-[11px] font-semibold",
                              statusLabel === "Active" &&
                                "bg-emerald-100 text-emerald-800",
                              statusLabel === "Pending Activation" &&
                                "bg-amber-100 text-amber-900",
                              statusLabel === "Disabled" &&
                                "bg-slate-200 text-slate-700"
                            )}
                          >
                            {statusLabel}
                          </span>
                        </div>
                      </div>
                    </div>
                  </>
                );
              })()}
            </div>
          )}
          <DialogFooter className="gap-2 border-t border-slate-100 px-6 py-4 sm:justify-between">
            {detailsEmployee && (
              <>
                <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
                  <Button
                    className="rounded-xl bg-[#1F456B] text-white hover:bg-[#17395D]"
                    onClick={() => {
                      openEdit(detailsEmployee);
                      setDetailsEmployee(null);
                    }}
                  >
                    Edit
                  </Button>
                  <Button
                    className="rounded-xl"
                    variant="outline"
                    asChild
                  >
                    <Link
                      to={`/owner/face-demo?employeeId=${detailsEmployee.id}`}
                      onClick={() => setDetailsEmployee(null)}
                    >
                      <ScanFace className="mr-2 h-4 w-4" />
                      Enroll face
                    </Link>
                  </Button>
                </div>
                {detailsEmployee.status === "inactive" ? (
                  <Button
                    className="rounded-xl bg-[#1F456B] text-white hover:bg-[#17395D]"
                    onClick={() => restore.mutate(detailsEmployee.id)}
                    disabled={restore.isPending}
                  >
                    Restore
                  </Button>
                ) : (
                  <Button
                    className="rounded-xl"
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
        <DialogContent className="gap-0 overflow-hidden p-0 sm:max-w-md sm:rounded-2xl">
          <DialogHeader className="border-b border-slate-100 px-6 pb-4 pt-6">
            <DialogTitle className="text-[#111827]">
              Employee Login Credentials
            </DialogTitle>
          </DialogHeader>
          {newCredentials && (
            <div className="space-y-4 px-6 py-5">
              <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[#1F456B] to-[#2A5A84] p-4 text-white">
                <div className="pointer-events-none absolute -right-6 -top-8 h-24 w-24 rounded-full bg-white/10" />
                <div className="relative flex items-center gap-3">
                  <div className="flex h-11 w-11 items-center justify-center rounded-full bg-white/15 ring-2 ring-[#B9D8EE]/40">
                    <KeyRound className="h-5 w-5" />
                  </div>
                  <div className="min-w-0">
                    <p className="truncate font-semibold">
                      {newCredentials.full_name}
                    </p>
                    <p className="text-sm text-white/75">
                      Ready to share login details
                    </p>
                  </div>
                </div>
              </div>
              <div className="space-y-3 rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4 text-sm shadow-sm">
                <p className="text-[13px] leading-relaxed text-[#6B7280]">
                  Share these credentials with the employee so they can activate
                  their account.
                </p>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]">
                    Username
                  </p>
                  <p className="mt-1 rounded-xl border border-slate-100 bg-white px-3 py-2.5 font-mono text-[#1F2937]">
                    {newCredentials.generated_username ?? newCredentials.username}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]">
                    Temporary Password
                  </p>
                  <p className="mt-1 rounded-xl border border-slate-100 bg-white px-3 py-2.5 font-mono text-[#1F2937]">
                    {newCredentials.temporary_password ?? "Hidden"}
                  </p>
                </div>
              </div>
            </div>
          )}
          <DialogFooter className="border-t border-slate-100 px-6 py-4 sm:justify-end">
            <Button
              className="rounded-xl bg-[#1F456B] hover:bg-[#2A5A84]"
              onClick={() => setNewCredentials(null)}
            >
              Done
            </Button>
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
  trailing?: ReactNode;
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
  const fieldClass =
    "h-11 rounded-xl border-slate-200 bg-white shadow-sm focus-visible:ring-[#1F456B]/30";
  const selectClass =
    "flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm shadow-sm outline-none focus:border-[#1F456B] focus:ring-2 focus:ring-[#1F456B]/20";

  return (
    <div className="space-y-4">
      {!editing && (
        <div className="flex gap-3 rounded-xl border border-[#D7E6F5] bg-[#F3F8FD] px-3.5 py-3">
          <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-white text-[#1F456B] shadow-sm">
            <KeyRound className="h-4 w-4" />
          </div>
          <p className="text-[13px] leading-relaxed text-[#334155]">
            Username and temporary password are generated automatically after
            enrollment. You’ll get them to share once the employee is added.
          </p>
        </div>
      )}
      {editing ? (
        <p className="text-sm text-[#6B7280]">
          Update the employee’s profile details below. Login credentials stay the
          same.
        </p>
      ) : null}
      <div className="space-y-2">
        <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]" htmlFor="employee-name">
          Full Name
        </Label>
        <Input
          className={fieldClass}
          id="employee-name"
          value={form.fullName}
          onChange={(event) =>
            onChange({ ...form, fullName: event.target.value })
          }
        />
      </div>
      <div className="space-y-2">
        <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]" htmlFor="employee-phone">
          Contact Number
        </Label>
        <Input
          className={fieldClass}
          id="employee-phone"
          value={form.phone}
          onChange={(event) =>
            onChange({ ...form, phone: event.target.value })
          }
        />
      </div>
      <div className="space-y-2">
        <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]" htmlFor="employee-position">
          Position/Role
        </Label>
        {positions.length > 0 ? (
          <select
            id="employee-position"
            className={selectClass}
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
            className={fieldClass}
            id="employee-position"
            value={form.positionTitle}
            onChange={(event) =>
              onChange({ ...form, positionTitle: event.target.value })
            }
          />
        )}
      </div>
      <div className="space-y-2">
        <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]" htmlFor="employee-type">
          Employment Type
        </Label>
        <select
          id="employee-type"
          className={selectClass}
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
      <div className="space-y-2">
        <Label
          className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]"
          htmlFor="employee-pay-basis"
        >
          Pay Basis
        </Label>
        <select
          id="employee-pay-basis"
          className={selectClass}
          value={form.payBasis}
          onChange={(event) => {
            const payBasis = event.target.value as PayBasis;
            const selected = positions.find((p) => p.id === form.positionId);
            onChange({
              ...form,
              payBasis,
              dailyRate:
                payBasis === "daily" &&
                !form.dailyRate.trim() &&
                selected?.daily_rate != null
                  ? String(selected.daily_rate)
                  : form.dailyRate,
            });
          }}
        >
          <option value="daily">Daily</option>
          <option value="hourly">Hourly</option>
          <option value="monthly">Monthly</option>
        </select>
      </div>
      {form.payBasis === "daily" ? (
        <div className="space-y-2">
          <Label
            className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]"
            htmlFor="employee-daily-rate"
          >
            Daily Rate (₱)
          </Label>
          <Input
            className={fieldClass}
            id="employee-daily-rate"
            type="number"
            min="0"
            step="0.01"
            value={form.dailyRate}
            onChange={(event) =>
              onChange({ ...form, dailyRate: event.target.value })
            }
          />
          <p className="text-xs text-[#6B7280]">
            Prefills from the selected position. You can override it for this
            employee. Payroll uses this employee daily rate (position rate is
            fallback only).
          </p>
        </div>
      ) : null}
      {form.payBasis === "hourly" ? (
        <div className="space-y-2">
          <Label
            className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]"
            htmlFor="employee-hourly-rate"
          >
            Hourly Rate (₱)
          </Label>
          <Input
            className={fieldClass}
            id="employee-hourly-rate"
            type="number"
            min="0"
            step="0.01"
            value={form.hourlyRate}
            onChange={(event) =>
              onChange({ ...form, hourlyRate: event.target.value })
            }
          />
        </div>
      ) : null}
      {form.payBasis === "monthly" ? (
        <div className="space-y-2">
          <Label
            className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]"
            htmlFor="employee-monthly-salary"
          >
            Monthly Salary (₱)
          </Label>
          <Input
            className={fieldClass}
            id="employee-monthly-salary"
            type="number"
            min="0"
            step="0.01"
            value={form.monthlySalary}
            onChange={(event) =>
              onChange({ ...form, monthlySalary: event.target.value })
            }
          />
        </div>
      ) : null}
    </div>
  );
}
