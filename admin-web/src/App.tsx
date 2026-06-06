import { Navigate, Route, Routes } from "react-router-dom";
import { AppLayout } from "@/layouts/AppLayout";
import { AdminRegistrationsPage } from "@/pages/AdminRegistrationsPage";
import { LoginPage } from "@/pages/LoginPage";
import { OwnerEmployeesPage } from "@/pages/OwnerEmployeesPage";
import { AdminDashboardPage } from "@/pages/AdminDashboardPage";
import { ApprovedBusinessPage } from "@/pages/ApprovedBusinessPage";
import { AdminProfilePage } from "@/pages/AdminProfilePage";
import { ActivityLogsPage } from "@/pages/ActivityLogsPage";
import { BusinessRegistrationPage } from "@/pages/BusinessRegistrationPage";

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = localStorage.getItem("aroll_token");
  if (!token) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/admin"
        element={
          <RequireAuth>
            <AppLayout nav={[
              { to: "/admin/dashboard", label: "Dashboard" },
              { to: "/admin/approved-business", label: "Approved Businesses" },
              { to: "/admin/registrations", label: "Registration Request" },
              { to: "/admin/activity-logs", label: "Activity Logs" },
              { to: "/admin/profile", label: "Profile" },
              ]} />
          </RequireAuth>
        }
      >
        <Route path="dashboard" element={<AdminDashboardPage />} />
        <Route path="approved-business" element={<ApprovedBusinessPage />} />
        <Route path="registrations" element={<AdminRegistrationsPage />} />
        <Route path="activity-logs" element={<ActivityLogsPage />} />
        <Route path="profile" element={<AdminProfilePage />} />
        <Route index element={<Navigate to="dashboard" replace />} />
      </Route>

      <Route
        path="/register-business"
        element={<BusinessRegistrationPage />}
      />

      <Route
        path="/owner"
        element={
          <RequireAuth>
            <AppLayout nav={[{ to: "/owner", label: "Employees" }]} />
          </RequireAuth>
        }
      >

        <Route index element={<OwnerEmployeesPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/login" replace />} />
    </Routes>
  );
}
