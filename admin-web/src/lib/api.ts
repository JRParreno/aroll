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

export type Registration = {
  id: string;
  business_name: string;
  owner_name: string;
  owner_email: string;
  owner_phone?: string;
  proposed_address?: string;
  status: string;
  submitted_at: string;
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

export async function listRegistrations(status?: string) {
  const params =
    status && status !== "all" ? { status_filter: status } : undefined;

  const { data } = await api.get<Registration[]>("/admin/registrations", {
    params,
  });

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
  const { data } = await api.get("/admin/dashboard-stats");
  return data;
}

export async function listBusinesses() {
  const { data } = await api.get("/admin/businesses");
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