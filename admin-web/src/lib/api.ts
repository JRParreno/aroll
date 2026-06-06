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

export async function getMe() {
  const { data } = await api.get<UserMe>("/auth/me");
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
  employment_type?: string;
  phone?: string;
}) {
  const { data } = await api.post<EmployeeCreateResponse>(
    "/employees",
    payload
  );
  return data;
}