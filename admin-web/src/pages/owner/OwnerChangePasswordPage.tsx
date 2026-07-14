import { useState } from "react";
import { ArrowRight, ShieldCheck } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  PasswordInput,
  PasswordRequirements,
} from "@/components/ui/password-input";
import { Button } from "@/components/ui/button";
import { changePassword, getMe } from "@/lib/api";
import { canSubmitPasswordChange, validatePassword } from "@/lib/passwordValidation";
import { ME_QUERY_KEY, setAuthSession } from "@/lib/authSession";

export function OwnerChangePasswordPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (newPassword !== confirmPassword) {
      toast.error("New passwords do not match");
      return;
    }

    const validation = validatePassword(newPassword);
    if (!validation.valid) {
      toast.error(validation.errors[0]);
      return;
    }

    setLoading(true);
    try {
      const res = await changePassword(currentPassword, newPassword);
      setAuthSession(res.access_token);
      const me = await getMe();
      qc.setQueryData(ME_QUERY_KEY, me);
      toast.success("Password updated successfully");
      navigate(me.setup_completed_at ? "/owner/dashboard" : "/owner/setup-wizard");
    } catch {
      toast.error("Failed to update password. Check your current password.");
    } finally {
      setLoading(false);
    }
  }

  const canSubmit = canSubmitPasswordChange({
    currentPassword,
    newPassword,
    confirmPassword,
  });

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827]">
      <main className="flex min-h-screen items-center justify-center px-5 py-8 sm:px-8 lg:px-12">
        <div className="w-full max-w-md">
          <div className="mb-8">
            <div className="mb-5 inline-flex items-center gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-xs font-medium text-[#1E3A5F]">
              <ShieldCheck className="h-4 w-4" />
              Security update
            </div>
            <h1 className="text-3xl font-semibold tracking-tight text-[#111827] sm:text-4xl">
              Change Password
            </h1>
            <p className="mt-3 text-sm leading-6 text-[#6B7280]">
              You must set a new password before accessing your dashboard.
            </p>
          </div>

          <section className="rounded-3xl border border-white/70 bg-white/75 p-5 shadow-sm backdrop-blur sm:p-7">
            <form onSubmit={handleSubmit} className="space-y-5">
              <PasswordInput
                id="current_password"
                label="Current Password"
                value={currentPassword}
                onChange={setCurrentPassword}
                required
                inputClassName="h-11 rounded-lg border-0 bg-white shadow-sm"
              />
              <PasswordInput
                id="new_password"
                label="New Password"
                value={newPassword}
                onChange={setNewPassword}
                required
                inputClassName="h-11 rounded-lg border-0 bg-white shadow-sm"
              />
              <PasswordInput
                id="confirm_password"
                label="Confirm New Password"
                value={confirmPassword}
                onChange={setConfirmPassword}
                required
                inputClassName="h-11 rounded-lg border-0 bg-white shadow-sm"
              />
              <PasswordRequirements
                password={newPassword}
                confirmPassword={confirmPassword}
              />
              <Button
                type="submit"
                className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                disabled={loading || !canSubmit}
              >
                {loading ? "Updating..." : "Update Password"}
                {!loading && <ArrowRight className="ml-2 h-4 w-4" />}
              </Button>
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
