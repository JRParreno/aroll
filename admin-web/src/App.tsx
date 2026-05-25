import { Navigate, Route, Routes } from "react-router-dom";
import { AppLayout } from "@/layouts/AppLayout";
import { AdminRegistrationsPage } from "@/pages/AdminRegistrationsPage";
import { LoginPage } from "@/pages/LoginPage";
import { OwnerEmployeesPage } from "@/pages/OwnerEmployeesPage";

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
            <AppLayout nav={[{ to: "/admin", label: "Registrations" }]} />
          </RequireAuth>
        }
      >
        <Route index element={<AdminRegistrationsPage />} />
      </Route>
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
