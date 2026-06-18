export type AuthSessionRole = "platform_admin" | "owner" | "manager";

const TOKEN_KEY = "aroll_token";

const OWNER_SESSION_KEYS = [
  "aroll_must_change_password",
  "aroll_business_code",
  "aroll_business_name",
  "aroll_session_role",
] as const;

/** Single profile cache for the one active session (token determines the user). */
export const ME_QUERY_KEY = ["me"] as const;

export function getAuthToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function isAdminRole(role: string): boolean {
  return role === "platform_admin";
}

export function isOwnerRole(role: string): boolean {
  return role === "owner" || role === "manager";
}

function clearOwnerSessionData() {
  for (const key of OWNER_SESSION_KEYS) {
    localStorage.removeItem(key);
  }
}

export function setAuthSession(token: string) {
  clearAuthSession();
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearAuthSession() {
  localStorage.removeItem(TOKEN_KEY);
  clearOwnerSessionData();
}
