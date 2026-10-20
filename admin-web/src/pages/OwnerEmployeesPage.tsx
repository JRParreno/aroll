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
  Mail,
  Plus,
  Scale,
  Search,
  Trash2,
  UserMinus,
  UserPlus,
} from "lucide-react";
import { useMemo, useState, type ReactNode } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { ConfirmActionDialog } from "@/components/ConfirmActionDialog";
import { SimulatedBadge } from "@/components/tenant/SimulatedBadge";
import { useTenantMode } from "@/lib/tenantMode";
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
  deactivateEmployee,
  deleteEmployee,
  getWeeklySchedule,
  listEmployees,
  listPositions,
  reactivateEmployee,
  updateEmployee,
  type Employee,
  type PayBasis,
  type Position,
} from "@/lib/api";
import { getWeekStart, toDateKey } from "@/components/owner/schedule/scheduleUtils";
import { cn } from "@/lib/utils";

type EmployeeForm = {
  fullName: string;
  positionTitle: string;
  positionId: string;
  employmentType: "full_time" | "part_time";
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

function positionPayConfigs(position: Position | undefined) {
  if (!position) return [] as NonNullable<Position["pay_configs"]>;
  if (position.pay_configs && position.pay_configs.length > 0) {
    return position.pay_configs;
  }
  const legacy: NonNullable<Position["pay_configs"]> = [];
  if (position.daily_rate != null && Number(position.daily_rate) > 0) {
    legacy.push({
      id: `${position.id}-daily`,
      pay_basis: "daily",
      rate: Number(position.daily_rate),
    });
  }
  if (position.hourly_rate != null && Number(position.hourly_rate) > 0) {
    legacy.push({
      id: `${position.id}-hourly`,
      pay_basis: "hourly",
      rate: Number(position.hourly_rate),
    });
  }
  return legacy;
}

function configRateForBasis(
  position: Position | undefined,
  basis: PayBasis
): number | null {
  if (basis !== "daily" && basis !== "hourly") return null;
  const match = positionPayConfigs(position).find((c) => c.pay_basis === basis);
  return match != null ? Number(match.rate) : null;
}

function availablePayBases(position: Position | undefined): Array<"daily" | "hourly"> {
  return positionPayConfigs(position).map((c) => c.pay_basis);
}

function ratesFromConfig(
  position: Position | undefined,
  basis: PayBasis
): Pick<EmployeeForm, "dailyRate" | "hourlyRate" | "monthlySalary"> {
  if (basis === "daily") {
    const rate = configRateForBasis(position, "daily");
    return {
      dailyRate: rate != null ? String(rate) : "",
      hourlyRate: "",
      monthlySalary: "",
    };
  }
  if (basis === "hourly") {
    const rate = configRateForBasis(position, "hourly");
    return {
      dailyRate: "",
      hourlyRate: rate != null ? String(rate) : "",
      monthlySalary: "",
    };
  }
  return { dailyRate: "", hourlyRate: "", monthlySalary: "" };
}

function formPayReady(form: EmployeeForm) {
  if (form.payBasis === "daily") return Number(form.dailyRate) > 0;
  if (form.payBasis === "hourly") return Number(form.hourlyRate) > 0;
  return Number(form.monthlySalary) > 0;
}

function formCompensationReady(
  form: EmployeeForm,
  positions: Position[],
  { allowLegacyMonthly = false }: { allowLegacyMonthly?: boolean } = {}
) {
  if (!form.positionId.trim()) return false;
  const selected = positions.find((p) => p.id === form.positionId);
  if (!selected) return false;
  if (form.payBasis === "monthly") {
    return allowLegacyMonthly && formPayReady(form);
  }
  const bases = availablePayBases(selected);
  if (!bases.includes(form.payBasis as "daily" | "hourly")) return false;
  return formPayReady(form);
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

function formatConsentStamp(value: string | null | undefined) {
  if (!value) return "Not recorded";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString();
}

function consentLine(
  satisfied: boolean | undefined,
  version: string | null | undefined,
  acceptedAt: string | null | undefined
) {
  if (!satisfied) return "Not accepted for the current published version";
  const versionLabel = version ? `v${version}` : "current version";
  return `${versionLabel} · ${formatConsentStamp(acceptedAt)}`;
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
      <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-[var(--owner-well)] text-[var(--owner-navy)]">
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
  const { isDemo } = useTenantMode();
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [formOpen, setFormOpen] = useState(false);
  const [detailsEmployee, setDetailsEmployee] = useState<Employee | null>(null);
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  const [newCredentials, setNewCredentials] = useState<Employee | null>(null);
  const [employeeToDelete, setEmployeeToDelete] = useState<Employee | null>(null);
  const [employeeToDeactivate, setEmployeeToDeactivate] = useState<Employee | null>(
    null
  );
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
    const bases = availablePayBases(selected);
    const preferred =
      bases.length === 1 ? bases[0] : bases.includes("daily") ? "daily" : bases[0];
    const apply = (current: EmployeeForm): EmployeeForm => {
      if (!nextPositionId || !selected) {
        return {
          ...current,
          positionId: "",
          positionTitle: "",
          payBasis: "daily",
          dailyRate: "",
          hourlyRate: "",
          monthlySalary: target === "edit" ? current.monthlySalary : "",
        };
      }
      if (!preferred) {
        return {
          ...current,
          positionId: nextPositionId,
          positionTitle: selected.title,
          payBasis: current.payBasis === "monthly" ? "monthly" : "daily",
          dailyRate: current.payBasis === "daily" ? current.dailyRate : "",
          hourlyRate: current.payBasis === "hourly" ? current.hourlyRate : "",
          monthlySalary:
            current.payBasis === "monthly" ? current.monthlySalary : "",
        };
      }
      return {
        ...current,
        positionId: nextPositionId,
        positionTitle: selected.title,
        payBasis: preferred,
        ...ratesFromConfig(selected, preferred),
      };
    };
    if (target === "create") setForm(apply);
    else setEditForm(apply);
  }

  function changeEmploymentType(
    nextType: EmployeeForm["employmentType"],
    target: "create" | "edit"
  ) {
    const apply = (current: EmployeeForm): EmployeeForm => ({
      ...current,
      employmentType: nextType,
      positionId: "",
      positionTitle: "",
      payBasis: "daily",
      dailyRate: "",
      hourlyRate: "",
      monthlySalary: target === "edit" ? current.monthlySalary : "",
    });
    if (target === "create") setForm(apply);
    else setEditForm(apply);
  }

  const create = useMutation({
    mutationFn: () =>
      createEmployee({
        full_name: form.fullName,
        position_title: form.positionTitle,
        position_id: form.positionId || undefined,
        employment_type: form.employmentType,
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

  const deactivate = useMutation({
    mutationFn: deactivateEmployee,
    onSuccess: () => {
      toast.success("Employee deactivated");
      setEmployeeToDeactivate(null);
      setDetailsEmployee(null);
      qc.invalidateQueries({ queryKey: ["employees"] });
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
          : "Failed to deactivate employee";
      toast.error(detail);
    },
  });

  function openEdit(employee: Employee) {
    const matchedPosition =
      positions.find((position) => position.id === (employee.position_id ?? "")) ??
      positions.find(
        (position) => position.title === (employee.position_title ?? "")
      );
    const employeeBasis = (employee.pay_basis ?? "daily") as PayBasis;
    const bases = availablePayBases(matchedPosition);
    const basisStillConfigured =
      employeeBasis === "daily" || employeeBasis === "hourly"
        ? bases.includes(employeeBasis)
        : false;

    let payBasis = employeeBasis;
    let dailyRate =
      employee.daily_rate != null ? String(employee.daily_rate) : "";
    let hourlyRate =
      employee.hourly_rate != null ? String(employee.hourly_rate) : "";
    let monthlySalary =
      employee.monthly_salary != null ? String(employee.monthly_salary) : "";

    if (matchedPosition && basisStillConfigured) {
      const configured = ratesFromConfig(matchedPosition, employeeBasis);
      payBasis = employeeBasis;
      dailyRate = configured.dailyRate;
      hourlyRate = configured.hourlyRate;
      monthlySalary = "";
    }

    setEditingEmployee(employee);
    setEditForm({
      fullName: employee.full_name,
      positionTitle: employee.position_title ?? "",
      positionId: matchedPosition?.id ?? employee.position_id ?? "",
      employmentType: employee.employment_type as EmployeeForm["employmentType"],
      payBasis,
      dailyRate,
      hourlyRate,
      monthlySalary,
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
    form.fullName.trim() &&
    form.positionId.trim() &&
    form.positionTitle.trim() &&
    formCompensationReady(form, positions);
  const editReady =
    editForm.fullName.trim() &&
    editForm.positionId.trim() &&
    editForm.positionTitle.trim() &&
    formCompensationReady(editForm, positions, { allowLegacyMonthly: true });

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Employees"
        description={
          isDemo
            ? "Simulated demo employees for research/defense presentation only."
            : "Search your team, open a profile, or enroll a new employee."
        }
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
            placeholder="Search by name, role, or username..."
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
          <div className="owner-empty">
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
                      <h2 className="truncate text-sm font-semibold text-[#1F2937] group-hover:text-[var(--owner-navy)]">
                        {employee.full_name}
                      </h2>
                      {isDemo ? (
                        <p className="mt-1">
                          <SimulatedBadge label="Demo Employee" />
                        </p>
                      ) : null}
                      {employee.recovery_email ? (
                        <div className="mt-2 flex items-center gap-2 text-[11px] font-medium text-[#6B7280]">
                          <Mail className="h-3.5 w-3.5 shrink-0 text-[#9CA3AF]" />
                          <span className="truncate">{employee.recovery_email}</span>
                        </div>
                      ) : null}
                      <div className="mt-2 flex items-center gap-2 text-[11px] font-medium text-[#6B7280]">
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
            <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[var(--owner-button)] to-[var(--owner-navy-soft)] p-4 text-white shadow-sm">
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
                onEmploymentTypeChange={(type) =>
                  changeEmploymentType(type, "create")
                }
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
              className="rounded-xl bg-[var(--owner-button)] hover:bg-[var(--owner-navy-soft)]"
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
              <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[var(--owner-button)] to-[var(--owner-navy-soft)] p-4 text-white shadow-sm">
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
                  onEmploymentTypeChange={(type) =>
                    changeEmploymentType(type, "edit")
                  }
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
              className="rounded-xl bg-[var(--owner-button)] text-white hover:bg-[var(--owner-navy-soft)]"
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
                    <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[var(--owner-button)] to-[var(--owner-navy-soft)] p-4 text-white shadow-sm">
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
                          {isDemo ? (
                            <p className="mt-1">
                              <SimulatedBadge label="Demo Employee" />
                            </p>
                          ) : null}
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
                      <DetailInfoRow
                        icon={<Mail className="h-4 w-4" />}
                        label="Recovery email"
                        value={detailsEmployee.recovery_email || "Not registered yet"}
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

                    <div>
                      <h3 className="mb-2 text-sm font-semibold text-[#111827]">
                        Consent records
                      </h3>
                      <div className="divide-y divide-slate-100 rounded-2xl border border-slate-200 bg-[#FAFBFC] px-3 py-1">
                        <DetailInfoRow
                          icon={<Scale className="h-4 w-4" />}
                          label="Terms"
                          value={consentLine(
                            detailsEmployee.consent?.terms_satisfied,
                            detailsEmployee.consent?.terms_version,
                            detailsEmployee.consent?.terms_accepted_at
                          )}
                        />
                        <DetailInfoRow
                          icon={<Scale className="h-4 w-4" />}
                          label="Privacy"
                          value={consentLine(
                            detailsEmployee.consent?.privacy_satisfied,
                            detailsEmployee.consent?.privacy_version,
                            detailsEmployee.consent?.privacy_accepted_at
                          )}
                        />
                        <DetailInfoRow
                          icon={<Scale className="h-4 w-4" />}
                          label="Biometric"
                          value={consentLine(
                            detailsEmployee.consent?.biometric_satisfied,
                            detailsEmployee.consent?.biometric_version,
                            detailsEmployee.consent?.biometric_accepted_at
                          )}
                        />
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
                    className="rounded-xl bg-[var(--owner-button)] text-white hover:bg-[var(--owner-navy-soft)]"
                    onClick={() => {
                      openEdit(detailsEmployee);
                      setDetailsEmployee(null);
                    }}
                    disabled={
                      deactivate.isPending || restore.isPending || remove.isPending
                    }
                  >
                    Edit
                  </Button>
                </div>
                <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
                  {detailsEmployee.status === "inactive" ? (
                    <Button
                      className="rounded-xl bg-[var(--owner-button)] text-white hover:bg-[var(--owner-navy-soft)]"
                      onClick={() => restore.mutate(detailsEmployee.id)}
                      disabled={
                        restore.isPending || deactivate.isPending || remove.isPending
                      }
                    >
                      Restore
                    </Button>
                  ) : (
                    <Button
                      className="rounded-xl bg-[var(--owner-button)] text-white hover:bg-[var(--owner-navy-soft)]"
                      onClick={() => setEmployeeToDeactivate(detailsEmployee)}
                      disabled={
                        deactivate.isPending || restore.isPending || remove.isPending
                      }
                    >
                      Deactivate
                    </Button>
                  )}
                  <Button
                    className="rounded-xl"
                    variant="destructive"
                    onClick={() => setEmployeeToDelete(detailsEmployee)}
                    disabled={
                      remove.isPending || deactivate.isPending || restore.isPending
                    }
                  >
                    Delete
                  </Button>
                </div>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmActionDialog
        open={Boolean(employeeToDeactivate)}
        onOpenChange={(open) => {
          if (!open && !deactivate.isPending) setEmployeeToDeactivate(null);
        }}
        icon={<UserMinus className="h-5 w-5" strokeWidth={2.25} aria-hidden />}
        title="Deactivate Employee?"
        description="This will disable the employee's account and employee access. Their existing attendance and payroll history will be preserved. You can reactivate the employee later."
        confirmLabel="Deactivate"
        tone="primary"
        cancelDisabled={deactivate.isPending}
        confirmDisabled={deactivate.isPending}
        onConfirm={() => {
          if (employeeToDeactivate && !deactivate.isPending) {
            deactivate.mutate(employeeToDeactivate.id);
          }
        }}
      />

      <ConfirmActionDialog
        open={Boolean(employeeToDelete)}
        onOpenChange={(open) => {
          if (!open && !remove.isPending) setEmployeeToDelete(null);
        }}
        icon={<Trash2 className="h-5 w-5" strokeWidth={2.25} aria-hidden />}
        title="Permanently Delete Employee?"
        description={
          <div className="space-y-3 text-left">
            <p>
              This action permanently removes this employee from the business.
            </p>
            <div>
              <p className="font-semibold text-[#4B5563]">
                The following will be deleted:
              </p>
              <ul className="mt-1.5 list-disc space-y-1 pl-5">
                <li>Employee profile and account access</li>
                <li>Face and attendance access data</li>
                <li>Attendance and schedule assignment records</li>
                <li>Payroll adjustments</li>
                <li>Employee schedule-template entries</li>
              </ul>
            </div>
            <p>
              Finalized payslips will be preserved for record-keeping, but they
              will no longer be linked to this employee account.
            </p>
            <p className="font-medium text-[#B91C1C]">
              This action cannot be undone. If you only want to prevent the
              employee from accessing the system while keeping their records,
              use Deactivate instead.
            </p>
          </div>
        }
        confirmLabel="Delete Permanently"
        tone="danger"
        cancelDisabled={remove.isPending}
        confirmDisabled={remove.isPending}
        onConfirm={() => {
          if (employeeToDelete) remove.mutate(employeeToDelete.id);
        }}
      />

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
              <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-[var(--owner-button)] to-[var(--owner-navy-soft)] p-4 text-white">
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
              className="rounded-xl bg-[var(--owner-button)] hover:bg-[var(--owner-navy-soft)]"
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
  onEmploymentTypeChange,
}: {
  form: EmployeeForm;
  positions: Position[];
  editing?: boolean;
  onChange: (form: EmployeeForm) => void;
  onPositionChange: (positionId: string) => void;
  onEmploymentTypeChange: (employmentType: EmployeeForm["employmentType"]) => void;
}) {
  const fieldClass =
    "h-11 rounded-xl border-slate-200 bg-white shadow-sm focus-visible:ring-[color-mix(in_srgb,var(--owner-navy)_30%,transparent)]";
  const selectClass =
    "flex h-11 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm shadow-sm outline-none focus:border-[var(--owner-navy)] focus:ring-2 focus:ring-[color-mix(in_srgb,var(--owner-navy)_20%,transparent)]";

  const configuredRoles = positions.filter(
    (p) => p.employment_type === form.employmentType
  );
  const selected = positions.find((p) => p.id === form.positionId);
  const roleOptions =
    editing &&
    selected &&
    !configuredRoles.some((p) => p.id === selected.id)
      ? [selected, ...configuredRoles]
      : configuredRoles;

  const bases = availablePayBases(selected);
  const basisConfigured =
    form.payBasis === "daily" || form.payBasis === "hourly"
      ? bases.includes(form.payBasis)
      : false;
  const isLegacyMonthly = form.payBasis === "monthly";
  const configuredRateLocked =
    Boolean(form.positionId) && (basisConfigured || isLegacyMonthly);
  const missingConfig =
    Boolean(form.positionId) &&
    !isLegacyMonthly &&
    (bases.length === 0 || !basisConfigured);

  const rateSummary =
    form.payBasis === "hourly"
      ? `Hourly · ₱${form.hourlyRate || "—"}/hr`
      : form.payBasis === "monthly"
        ? `Monthly · ₱${form.monthlySalary || "—"} (legacy)`
        : `Daily · ₱${form.dailyRate || "—"}/day`;

  return (
    <div className="space-y-4">
      {!editing && (
        <div className="flex gap-3 rounded-xl border border-[#D7E6F5] bg-[#F3F8FD] px-3.5 py-3">
          <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-white text-[var(--owner-navy)] shadow-sm">
            <KeyRound className="h-4 w-4" />
          </div>
          <p className="text-[13px] leading-relaxed text-[#334155]">
            Username and temporary password are generated automatically after
            enrollment. You’ll get them to share once the employee is added.
            Choose employment type, role, then pay basis — the rate comes from
            Setup Wizard and cannot be typed here.
          </p>
        </div>
      )}
      {editing ? (
        <p className="text-sm text-[#6B7280]">
          Update the employee’s profile details below. Login credentials stay the
          same. Configured rates are read-only from Setup Wizard.
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
        <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]" htmlFor="employee-type">
          1. Employment Type
        </Label>
        <select
          id="employee-type"
          className={selectClass}
          value={form.employmentType}
          onChange={(event) =>
            onEmploymentTypeChange(
              event.target.value as EmployeeForm["employmentType"]
            )
          }
        >
          <option value="full_time">Full-Time</option>
          <option value="part_time">Part-Time</option>
        </select>
      </div>
      <div className="space-y-2">
        <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]" htmlFor="employee-position">
          2. Role / Position
        </Label>
        {roleOptions.length > 0 ? (
          <select
            id="employee-position"
            className={selectClass}
            value={form.positionId}
            onChange={(event) => onPositionChange(event.target.value)}
          >
            <option value="">Select role</option>
            {roleOptions.map((position) => (
              <option key={position.id} value={position.id}>
                {position.title}
                {!position.employment_type ? " (unclassified)" : ""}
              </option>
            ))}
          </select>
        ) : (
          <div className="rounded-xl border border-dashed border-slate-300 bg-white px-3 py-3 text-sm text-[#6B7280]">
            No roles configured for{" "}
            {form.employmentType === "part_time" ? "Part-time" : "Full-time"}.
            Add them in Business Setup → Positions & Salary Rates.
          </div>
        )}
      </div>
      {form.positionId ? (
        <div className="space-y-2">
          <Label
            className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]"
            htmlFor="employee-pay-basis"
          >
            3. Pay Basis
          </Label>
          <select
            id="employee-pay-basis"
            className={selectClass}
            value={
              isLegacyMonthly && !basisConfigured
                ? "monthly"
                : basisConfigured
                  ? form.payBasis
                  : ""
            }
            onChange={(event) => {
              const payBasis = event.target.value as PayBasis;
              if (payBasis !== "daily" && payBasis !== "hourly") return;
              onChange({
                ...form,
                payBasis,
                ...ratesFromConfig(selected, payBasis),
              });
            }}
          >
            <option value="">Select pay basis</option>
            {bases.map((basis) => (
              <option key={basis} value={basis}>
                {basis === "hourly" ? "Hourly" : "Daily"}
              </option>
            ))}
            {isLegacyMonthly ? (
              <option value="monthly">Monthly (legacy)</option>
            ) : null}
          </select>
          {missingConfig ? (
            <p className="text-xs text-amber-800">
              This employee’s previous pay basis is no longer configured for
              this role. Select a valid Daily or Hourly option before saving.
            </p>
          ) : null}
          {isLegacyMonthly ? (
            <p className="text-xs text-amber-800">
              Monthly pay is a legacy employee setting. To change compensation,
              select a configured Daily or Hourly option for this role.
            </p>
          ) : null}
        </div>
      ) : null}
      {configuredRateLocked || missingConfig ? (
        <div className="space-y-2">
          <Label className="text-xs font-semibold uppercase tracking-wide text-[#9CA3AF]">
            4. Configured Rate
          </Label>
          <div className="rounded-xl border border-slate-200 bg-slate-50 px-3 py-3 text-sm font-medium text-[#1F2937]">
            {rateSummary}
            {missingConfig ? " · not in Setup Wizard" : ""}
          </div>
          {configuredRateLocked && !missingConfig ? (
            <p className="text-xs text-[#6B7280]">
              Rate is configured in Setup Wizard. To change this rate, update the
              Setup Wizard configuration.
            </p>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
