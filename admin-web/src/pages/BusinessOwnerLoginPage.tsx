import { useState } from "react";
import { ArrowRight, BadgeCheck, Building2, Mail } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { SystemBrandPanel } from "@/components/branding/SystemBranding";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/ui/password-input";
import { businessOwnerLogin, getMe } from "@/lib/api";
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
        navigate("/owner/dashboard");
      }
    } catch {
      toast.error("Invalid business code, email, or password");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[minmax(300px,38vw)_1fr]">
      <SystemBrandPanel />

      <main className="flex min-h-screen items-center justify-center px-5 py-8 sm:px-8 lg:px-12">
        <div className="w-full max-w-md">
          <div className="mb-8">
            <div className="mb-5 inline-flex items-center gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-xs font-medium text-[#1E3A5F]">
              <BadgeCheck className="h-4 w-4" />
              Owner portal
            </div>
            <h1 className="text-3xl font-semibold tracking-tight text-[#111827] sm:text-4xl">
              Welcome back
            </h1>
            <p className="mt-3 text-sm leading-6 text-[#6B7280]">
              Sign in with your business code and owner credentials.
            </p>
          </div>

          <section className="rounded-3xl border border-white/70 bg-white/75 p-5 shadow-sm backdrop-blur sm:p-7">
            <form onSubmit={handleSubmit} className="space-y-5">
              <div className="space-y-2">
                <Label htmlFor="business_code">Business Code</Label>
                <div className="relative">
                  <Building2 className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                  <Input
                    id="business_code"
                    type="text"
                    placeholder="MB-D90987"
                    value={businessCode}
                    onChange={(e) => setBusinessCode(e.target.value)}
                    required
                    className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="email">Email Address</Label>
                <div className="relative">
                  <Mail className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                  <Input
                    id="email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                  />
                </div>
              </div>

              <PasswordInput
                id="password"
                label="Password"
                value={password}
                onChange={setPassword}
                required
                inputClassName="h-11 rounded-lg border-0 bg-white shadow-sm"
              />

              <Button
                type="submit"
                className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                disabled={loading}
              >
                {loading ? "Signing in..." : "Login"}
                {!loading && <ArrowRight className="ml-2 h-4 w-4" />}
              </Button>

              <div className="grid gap-3 pt-1 text-center text-xs text-[#6B7280] sm:grid-cols-2">
                <p>
                  Not yet registered?{" "}
                  <Link
                    to="/register-business"
                    className="font-medium text-[#1E3A5F] underline underline-offset-2"
                  >
                    Register here
                  </Link>
                </p>
                <p>
                  Already applied?{" "}
                  <Link
                    to="/track-registration"
                    className="font-medium text-[#1E3A5F] underline underline-offset-2"
                  >
                    Track status
                  </Link>
                </p>
              </div>
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
