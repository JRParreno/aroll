import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { businessOwnerLogin } from "@/lib/api";

export function BusinessOwnerLoginPage() {
  const navigate = useNavigate();
  const [businessCode, setBusinessCode] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await businessOwnerLogin(
        businessCode.trim(),
        email,
        password
      );
      localStorage.setItem("aroll_token", res.access_token);
      localStorage.setItem(
        "aroll_must_change_password",
        String(res.must_change_password)
      );
      localStorage.setItem("aroll_business_code", businessCode.trim());

      if (res.must_change_password) {
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
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Business Owner Login</CardTitle>
          <p className="text-sm text-muted-foreground">
            Sign in with your business code and owner credentials
          </p>
        </CardHeader>

        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="business_code">Business Code</Label>
              <Input
                id="business_code"
                type="text"
                placeholder="MB-D90987"
                value={businessCode}
                onChange={(e) => setBusinessCode(e.target.value)}
                required
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
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>

            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? "Signing in…" : "Login"}
            </Button>

            <p className="text-center text-xs text-muted-foreground">
              Not yet registered?{" "}
              <Link
                to="/register-business"
                className="underline underline-offset-2"
              >
                Register here
              </Link>
            </p>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
