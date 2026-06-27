import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowRight, LockKeyhole, Mail, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { SystemBrandPanel } from "@/components/branding/SystemBranding";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { login, getMe } from "@/lib/api";
import { ME_QUERY_KEY, setAuthSession } from "@/lib/authSession";
import { jwtDecode } from "jwt-decode";

type JwtPayload = { role?: string };

export function LoginPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [email, setEmail] = useState("admin@example.com");
  const [password, setPassword] = useState("changeme123");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await login(email, password);
      const decoded = jwtDecode<JwtPayload>(res.access_token);
      const role = decoded.role;

      if (role !== "platform_admin") {
        toast.error("Use the Business Owner Login page for owner accounts.");
        return;
      }

      qc.clear();
      setAuthSession(res.access_token);
      const me = await getMe();
      qc.setQueryData(ME_QUERY_KEY, me);
      navigate("/admin");
    } catch {
      toast.error("Invalid email or password");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[minmax(300px,38vw)_1fr]">
      <SystemBrandPanel description="Platform administration for business verification and oversight" />

      <main className="flex min-h-screen items-center justify-center px-5 py-8 sm:px-8 lg:px-12">
        <div className="w-full max-w-md">
          <div className="mb-8">
            <div className="mb-5 inline-flex items-center gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-xs font-medium text-[#1E3A5F]">
              <ShieldCheck className="h-4 w-4" />
              Admin portal
            </div>
            <h1 className="text-3xl font-semibold tracking-tight text-[#111827] sm:text-4xl">
              Welcome back
            </h1>
            <p className="mt-3 text-sm leading-6 text-[#6B7280]">
              Sign in to review registrations, monitor businesses, and manage
              platform activity.
            </p>
          </div>

          <section className="rounded-3xl border border-white/70 bg-white/80 p-5 shadow-sm backdrop-blur sm:p-7">
            <form onSubmit={handleSubmit} className="space-y-5">
              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <div className="relative">
                  <Mail className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                  <Input
                    id="email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                    autoComplete="email"
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="password">Password</Label>
                <div className="relative">
                  <LockKeyhole className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                  <Input
                    id="password"
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                    autoComplete="current-password"
                  />
                </div>
              </div>

              <Button
                type="submit"
                className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                disabled={loading}
              >
                {loading ? "Signing in..." : "Sign in"}
                {!loading && <ArrowRight className="ml-2 h-4 w-4" />}
              </Button>

              <p className="text-center text-xs text-[#6B7280]">
                Demo admin: admin@example.com / changeme123
              </p>
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
