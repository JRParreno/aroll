import { Navigate, Route, Routes } from "react-router-dom";
import { AppLayout } from "@/layouts/AppLayout";
import { OwnerLayout } from "@/layouts/OwnerLayout";
import { RequireOwnerAuth } from "@/layouts/RequireOwnerAuth";
import { AdminRegistrationsPage } from "@/pages/AdminRegistrationsPage";
import { LoginPage } from "@/pages/LoginPage";
import { BusinessOwnerLoginPage } from "@/pages/BusinessOwnerLoginPage";
import { OwnerEmployeesPage } from "@/pages/OwnerEmployeesPage";
import { AdminDashboardPage } from "@/pages/AdminDashboardPage";
import { ApprovedBusinessPage } from "@/pages/ApprovedBusinessPage";
import { BusinessDetailPage } from "@/pages/BusinessDetailPage";
import { AdminProfilePage } from "@/pages/AdminProfilePage";
import { ActivityLogsPage } from "@/pages/ActivityLogsPage";
import { BusinessRegistrationPage } from "@/pages/BusinessRegistrationPage";
import { TrackRegistrationPage } from "@/pages/TrackRegistrationPage";
import { RegistrationDetailPage } from "@/pages/RegistrationDetailPage";
import { AdminNotFoundPage } from "@/pages/AdminNotFoundPage";
import { OwnerDashboardPage } from "@/pages/owner/OwnerDashboardPage";
import { OwnerChangePasswordPage } from "@/pages/owner/OwnerChangePasswordPage";
import { OwnerSchedulePage } from "@/pages/owner/OwnerSchedulePage";
import { OwnerAttendancePage } from "@/pages/owner/OwnerAttendancePage";
import { OwnerPayrollPage } from "@/pages/owner/OwnerPayrollPage";
import { OwnerProductivityPage } from "@/pages/owner/OwnerProductivityPage";
import { OwnerLocationPage } from "@/pages/owner/OwnerLocationPage";
import { OwnerBusinessDocumentsPage } from "@/pages/owner/OwnerBusinessDocumentsPage";
import { OwnerPositionsSalaryRatesPage } from "@/pages/owner/OwnerPositionsSalaryRatesPage";
import { OwnerPayrollSchedulePage } from "@/pages/owner/OwnerPayrollSchedulePage";
import { OwnerPersonalSettingsPage } from "@/pages/owner/OwnerPersonalSettingsPage";
import { OwnerAccountSettingsPage } from "@/pages/owner/OwnerAccountSettingsPage";
import { OwnerBusinessSettingsPage } from "@/pages/owner/OwnerBusinessSettingsPage";
import { OwnerBusinessSetupsPage } from "@/pages/owner/OwnerBusinessSetupsPage";
import { OwnerHelpPage } from "@/pages/owner/OwnerHelpPage";
import { OwnerSetupWizardPage } from "@/pages/owner/setup/OwnerSetupWizardPage";
import { PendingVerificationPage } from "@/pages/owner/PendingVerificationPage";
import { RejectedApplicationPage } from "@/pages/owner/RejectedApplicationPage";

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = localStorage.getItem("aroll_token");
  if (!token) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/owner-login" element={<BusinessOwnerLoginPage />} />

      <Route
        path="/owner/change-password"
        element={
          <RequireOwnerAuth passwordChangeOnly>
            <OwnerChangePasswordPage />
          </RequireOwnerAuth>
        }
      />

      <Route
        path="/owner/setup-wizard"
        element={
          <RequireOwnerAuth>
            <OwnerSetupWizardPage />
          </RequireOwnerAuth>
        }
      />

      <Route
        path="/owner"
        element={
          <RequireOwnerAuth>
            <OwnerLayout />
          </RequireOwnerAuth>
        }
      >
        <Route path="dashboard" element={<OwnerDashboardPage />} />
        <Route path="employees" element={<OwnerEmployeesPage />} />
        <Route path="schedule" element={<OwnerSchedulePage />} />
        <Route path="attendance" element={<OwnerAttendancePage />} />
        <Route path="payroll" element={<OwnerPayrollPage />} />
        <Route path="productivity" element={<OwnerProductivityPage />} />
        <Route path="location" element={<OwnerLocationPage />} />
        <Route
          path="business-documents"
          element={<OwnerBusinessDocumentsPage />}
        />
        <Route
          path="positions-salary-rates"
          element={<OwnerPositionsSalaryRatesPage />}
        />
        <Route path="payroll-schedule" element={<OwnerPayrollSchedulePage />} />
        <Route path="settings/personal" element={<OwnerPersonalSettingsPage />} />
        <Route path="settings/account" element={<OwnerAccountSettingsPage />} />
        <Route path="settings/business" element={<OwnerBusinessSettingsPage />} />
        <Route path="settings/setup" element={<OwnerBusinessSetupsPage />} />
        <Route path="help" element={<OwnerHelpPage />} />
        <Route index element={<Navigate to="dashboard" replace />} />
      </Route>

      <Route
        path="/admin"
        element={
          <RequireAuth>
            <AppLayout
              nav={[
                { to: "/admin/dashboard", label: "Dashboard" },
                { to: "/admin/approved-business", label: "Approved Businesses" },
                { to: "/admin/registrations", label: "Registration Request" },
                { to: "/admin/activity-logs", label: "Activity Logs" },
                { to: "/admin/profile", label: "Profile" },
              ]}
            />
          </RequireAuth>
        }
      >
        <Route path="dashboard" element={<AdminDashboardPage />} />
        <Route path="approved-business" element={<ApprovedBusinessPage />} />
        <Route path="approved-business/:id" element={<BusinessDetailPage />} />
        <Route path="registrations" element={<AdminRegistrationsPage />} />
        <Route path="registrations/:id" element={<RegistrationDetailPage />} />
        <Route path="activity-logs" element={<ActivityLogsPage />} />
        <Route path="profile" element={<AdminProfilePage />} />
        <Route index element={<Navigate to="dashboard" replace />} />
        <Route path="*" element={<AdminNotFoundPage />} />
      </Route>

      <Route path="/register-business" element={<BusinessRegistrationPage />} />
      <Route path="/track-registration" element={<TrackRegistrationPage />} />
      <Route path="/pending-verification" element={<PendingVerificationPage />} />
      <Route path="/rejected-application" element={<RejectedApplicationPage />} />

      <Route path="*" element={<Navigate to="/login" replace />} />
    </Routes>
  );
}
