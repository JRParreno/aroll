import axios from "axios";

const API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8000/api/v1";

export const api = axios.create({ baseURL: API_BASE });

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("aroll_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

export type LoginResponse = {
  access_token: string;
  must_change_password: boolean;
};

export type UserMe = {
  id: string;
  email: string;
  role: string;
  business_id: string | null;
  must_change_password: boolean;
  full_name: string | null;
  business_name: string | null;
  business_code: string | null;
  setup_completed_at: string | null;
};

export type Registration = {
  id: string;
  business_name: string;
  owner_name: string;
  owner_email: string;
  owner_phone?: string | null;
  proposed_address?: string | null;
  status: string;
  submitted_at: string;
  reviewed_at?: string | null;
  rejection_reason?: string | null;
};

export type BusinessListItem = {
  id: string;
  business_code: string;
  name: string;
  status: string;
  timezone: string;
  created_at: string;
  employee_count: number;
  location_count: number;
};

export type BusinessLocation = {
  id: string;
  label: string;
  address: string;
  latitude: number | null;
  longitude: number | null;
  geofence_radius_m: number;
  is_primary: boolean;
};

export type BusinessDetail = {
  id: string;
  business_code: string;
  name: string;
  status: string;
  timezone: string;
  created_at: string;
  employee_count: number;
  owner: {
    name: string;
    email: string;
    phone: string | null;
  } | null;
  registration_submitted_at: string | null;
  locations: BusinessLocation[];
};

export type DashboardStats = {
  total_businesses: number;
  active_businesses: number;
  pending_requests: number;
  total_employees: number;
  monthly_registrations: { month: string; count: number }[];
  attendance_summary: {
    present: number;
    absent: number;
    late: number;
    present_rate: number;
    has_data: boolean;
  };
  recent_activities: {
    id: string;
    description: string;
    created_at: string;
  }[];
};

export type Employee = {
  id: string;
  email: string;
  full_name: string;
  position_title: string | null;
  employment_type: string;
  is_active: boolean;
};

export type EmployeeCreateResponse = Employee & {
  temporary_password: string;
};

export async function login(email: string, password: string) {
  const { data } = await api.post<LoginResponse>("/auth/login", {
    email,
    password,
  });
  return data;
}

export async function businessOwnerLogin(
  business_code: string,
  email: string,
  password: string
) {
  const { data } = await api.post<LoginResponse>(
    "/auth/business-owner-login",
    { business_code, email, password }
  );
  return data;
}

export async function getMe() {
  const { data } = await api.get<UserMe>("/auth/me");
  return data;
}

export async function changePassword(
  current_password: string,
  new_password: string
) {
  const { data } = await api.post<LoginResponse>("/auth/change-password", {
    current_password,
    new_password,
  });
  return data;
}

export async function listRegistrations(status?: string) {
  const params =
    status && status !== "all" ? { status_filter: status } : undefined;

  const { data } = await api.get<Registration[]>("/admin/registrations", {
    params,
  });

  return data;
}

export async function getRegistration(id: string) {
  const { data } = await api.get<Registration>(`/admin/registrations/${id}`);
  return data;
}

export async function rejectRegistration(
  id: string,
  rejection_reason: string
) {
  const { data } = await api.post(
    `/admin/registrations/${id}/reject`,
    { rejection_reason }
  );

  return data;
}

export async function approveRegistration(id: string) {
  const { data } = await api.post(`/admin/registrations/${id}/approve`);
  return data;
}

export async function submitRegistration(payload: {
  business_name: string;
  owner_name: string;
  owner_email: string;
  owner_phone: string;
  proposed_address: string;
}) {
  const { data } = await api.post("/registrations", payload);
  return data;
}

export async function getDashboardStats() {
  const { data } = await api.get<DashboardStats>("/admin/dashboard-stats");
  return data;
}

export async function listBusinesses() {
  const { data } = await api.get<BusinessListItem[]>("/admin/businesses");
  return data;
}

export async function getBusiness(id: string) {
  const { data } = await api.get<BusinessDetail>(`/admin/businesses/${id}`);
  return data;
}

export async function listEmployees() {
  const { data } = await api.get<Employee[]>("/employees");
  return data;
}

export async function listActivityLogs() {
  const { data } = await api.get("/admin/activity-logs");
  return data;
}

export async function createEmployee(payload: {
  email: string;
  full_name: string;
  position_title?: string;
  position_id?: string;
  employment_type?: string;
  phone?: string;
}) {
  const { data } = await api.post<EmployeeCreateResponse>(
    "/employees",
    payload
  );
  return data;
}

export type SetupStepStatus = {
  key: string;
  label: string;
  complete: boolean;
};

export type SetupStatus = {
  setup_completed_at: string | null;
  completion_percent: number;
  completed_steps: number;
  total_steps: number;
  steps: SetupStepStatus[];
  missing_items: string[];
};

export type Shift = {
  id: string;
  name: string;
  shift_type: string;
  start_time: string;
  end_time: string;
  break_minutes: number;
  employee_capacity: number;
  color: string | null;
  is_active: boolean;
};

export type ScheduleAssignment = {
  id: string;
  shift_id: string;
  employee_id: string;
  work_date: string;
  employee_name: string;
  shift_name: string;
  shift_start_time: string;
  shift_end_time: string;
  shift_color: string | null;
};

export type WeeklySchedule = {
  week_start: string;
  week_end: string;
  assignments: ScheduleAssignment[];
};

export type Position = {
  id: string;
  title: string;
  daily_rate: number;
  description: string | null;
  is_active: boolean;
};

export type PayrollConfig = {
  pay_period_type: string;
  next_payday_date: string | null;
  auto_reset_payroll_cycle: boolean;
  late_deduction_enabled: boolean;
  late_deduction_per_minute: number;
  overtime_enabled: boolean;
  overtime_per_minute: number;
};

export type AttendancePolicy = {
  early_clock_in_minutes: number;
  on_time_grace_minutes: number;
  half_day_threshold_minutes: number;
  absent_threshold_minutes: number;
  early_out_deduction_enabled: boolean;
  early_out_deduction_per_minute: number;
  overtime_enabled: boolean;
  overtime_minimum_minutes: number;
  overtime_rate_per_minute: number;
  missing_clock_out_policy: string;
  attendance_based_salary_enabled: boolean;
};

export type RestDayPolicy = {
  weekly_rest_day: string;
  work_on_rest_day_allowed: boolean;
  rest_day_premium_percent: number;
  use_custom_premium: boolean;
  custom_premium_percent: number | null;
};

export type Holiday = {
  id: string;
  business_id: string | null;
  name: string;
  holiday_date: string;
  is_paid: boolean;
  holiday_type: string;
  is_active: boolean;
};

export async function getSetupStatus() {
  const { data } = await api.get<SetupStatus>("/businesses/me/setup-status");
  return data;
}

export async function completeSetup() {
  const { data } = await api.post("/businesses/me/complete-setup");
  return data;
}

export async function listShifts() {
  const { data } = await api.get<Shift[]>("/shifts");
  return data;
}

export async function createShift(payload: {
  name: string;
  shift_type: string;
  start_time: string;
  end_time: string;
  break_minutes?: number;
  employee_capacity?: number;
}) {
  const { data } = await api.post<Shift>("/shifts", payload);
  return data;
}

export async function deleteShift(id: string) {
  const { data } = await api.delete(`/shifts/${id}`);
  return data;
}

export async function listPositions() {
  const { data } = await api.get<Position[]>("/positions");
  return data;
}

export async function createPosition(payload: {
  title: string;
  daily_rate: number;
  description?: string;
}) {
  const { data } = await api.post<Position>("/positions", payload);
  return data;
}

export async function deletePosition(id: string) {
  const { data } = await api.delete(`/positions/${id}`);
  return data;
}

export async function getPayrollConfig() {
  const { data } = await api.get<PayrollConfig>("/businesses/me/payroll-config");
  return data;
}

export async function updatePayrollConfig(payload: Partial<PayrollConfig>) {
  const { data } = await api.put("/businesses/me/payroll-config", payload);
  return data;
}

export async function getAttendancePolicy() {
  const { data } = await api.get<AttendancePolicy>(
    "/businesses/me/attendance-policy"
  );
  return data;
}

export async function updateAttendancePolicy(payload: Partial<AttendancePolicy>) {
  const { data } = await api.put("/businesses/me/attendance-policy", payload);
  return data;
}

export async function getRestDayPolicy() {
  const { data } = await api.get<RestDayPolicy>("/businesses/me/rest-day-policy");
  return data;
}

export async function updateRestDayPolicy(payload: Partial<RestDayPolicy>) {
  const { data } = await api.put("/businesses/me/rest-day-policy", payload);
  return data;
}

export async function listHolidays() {
  const { data } = await api.get<Holiday[]>("/holidays");
  return data;
}

export async function seedDefaultHolidays() {
  const { data } = await api.post<Holiday[]>("/holidays/seed-defaults");
  return data;
}

export async function createHoliday(payload: {
  name: string;
  holiday_date: string;
  is_paid?: boolean;
  holiday_type?: string;
}) {
  const { data } = await api.post<Holiday>("/holidays", payload);
  return data;
}

export async function getWeeklySchedule(weekStart: string) {
  const { data } = await api.get<WeeklySchedule>("/schedules/weekly", {
    params: { week_start: weekStart },
  });
  return data;
}

export async function assignSchedule(payload: {
  shift_id: string;
  work_date: string;
  employee_ids: string[];
}) {
  const { data } = await api.post<{
    created: number;
    assignments: ScheduleAssignment[];
  }>("/schedules/assign", payload);
  return data;
}

export type BusinessLocationConfig = {
  label: string;
  address: string;
  latitude: number | null;
  longitude: number | null;
  geofence_radius_m: number;
};

export async function getBusinessLocation() {
  const { data } = await api.get<BusinessLocationConfig>(
    "/businesses/me/location"
  );
  return data;
}

export async function updateBusinessLocation(payload: BusinessLocationConfig) {
  const { data } = await api.put("/businesses/me/location", payload);
  return data;
}