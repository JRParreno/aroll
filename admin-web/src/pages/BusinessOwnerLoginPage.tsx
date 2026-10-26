import { useState } from "react";
import { ArrowRight } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  PublicLogoMark,
  PublicPage,
  publicFieldClass,
  publicPrimaryButtonClass,
} from "@/components/marketing/PublicPage";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/ui/password-input";
import { businessOwnerLogin, getMe } from "@/lib/api";
import { ownerFirstLoginPath } from "@/lib/ownerFirstLoginPath";
import {
  clearAuthSession,
  isOwnerRole,
  ME_QUERY_KEY,
  setAuthSession,
} from "@/lib/authSession";

export function BusinessOwnerLoginPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [businessCode, setBusinessCode] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await businessOwnerLogin(
        businessCode.trim().toUpperCase().replace(/\s+/g, ""),
        email,
        password
      );

      qc.clear();
      setAuthSession(res.access_token);

      const me = await getMe();

      if (!isOwnerRole(me.role)) {
        clearAuthSession();
        qc.clear();
        toast.error("This account is not a business owner account.");
        return;
      }

      localStorage.setItem("aroll_business_code", businessCode.trim());
      qc.setQueryData(ME_QUERY_KEY, me);

      if (me.must_change_password) {
        toast.success("Signed in. Please change your password to continue.");
        navigate("/owner/change-password");
      } else {
        toast.success("Signed in successfully");
        navigate(ownerFirstLoginPath(me));
      }
    } catch {
      toast.error("Invalid business code, email, or password");
    } finally {
      setLoading(false);
    }
  }

  return (
    <PublicPage showHeaderLogo={false}>
      <div className="flex w-full flex-1 lg:items-center">
        <div className="grid w-full items-start gap-8 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)] lg:items-center lg:gap-16">
          <section>
            <PublicLogoMark className="aspect-[250/168] w-[128px] sm:w-[144px] lg:w-[160px]" />
            <p className="mt-7 text-xs font-semibold uppercase tracking-[0.18em] text-[#93C5FD]">
              Owner workspace
            </p>
            <h1 className="mt-2 max-w-[540px] text-[32px] font-semibold leading-[1.15] tracking-tight text-white lg:text-[46px]">
              Attendance and payroll,
              <br />
              in one workspace.
            </h1>
            <p className="mt-3 max-w-[520px] text-base leading-7 text-[#B7C3D7]">
              Employees record time in and time out with face recognition. Owners review schedules, leave, and payslips without leaving Aroll+.
            </p>
          </section>

        <section className="w-full rounded-2xl bg-white p-5 text-[#172554] shadow-xl shadow-black/25 sm:p-6">
          <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-[#2563EB]">
            Business owner
          </p>
          <h2 className="mt-2 text-2xl font-semibold text-[#172554]">Sign in</h2>
          <p className="mt-1 text-sm text-[#475569]">
            Use your business code and owner credentials.
          </p>
          <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            <div className="space-y-2">
              <Label htmlFor="business_code">Business Code</Label>
              <Input
                id="business_code"
                type="text"
                placeholder="MB-D90987"
                value={businessCode}
                onChange={(e) => setBusinessCode(e.target.value)}
                required
                className={publicFieldClass}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email Address</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className={publicFieldClass}
              />
            </div>
            <PasswordInput
              id="password"
              label="Password"
              value={password}
              onChange={setPassword}
              required
              inputClassName={publicFieldClass}
            />
            <div className="text-right">
              <Link
                to="/owner-forgot-password"
                className="text-sm font-medium text-[#1D4ED8] underline-offset-2 hover:underline"
              >
                Forgot password?
              </Link>
            </div>
            <Button type="submit" className={`w-full ${publicPrimaryButtonClass}`} disabled={loading}>
              {loading ? "Signing in..." : "Login"}
              {!loading && <ArrowRight className="ml-2 h-4 w-4" />}
            </Button>
            <div className="flex flex-col items-center gap-2 pt-1 text-center text-sm text-[#475569]">
              <p>
                Not yet registered?{" "}
                <Link to="/register-business" className="font-medium text-[#1D4ED8] hover:underline">
                  Register here
                </Link>
              </p>
              <p>
                Already applied?{" "}
                <Link to="/track-registration" className="font-medium text-[#1D4ED8] hover:underline">
                  Track status
                </Link>
              </p>
            </div>
          </form>
        </section>
        </div>
      </div>
    </PublicPage>
  );
}
