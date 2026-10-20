import { useEffect, useState } from "react";
import axios from "axios";
import { ArrowLeft, BadgeCheck, Building2, Mail } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { SystemBrandPanel } from "@/components/branding/SystemBranding";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/ui/password-input";
import {
  completeOwnerPasswordReset,
  ownerPasswordResetStatus,
  requestOwnerPasswordReset,
  verifyOwnerPasswordReset,
  type OwnerPasswordResetTicket,
} from "@/lib/api";
import { passwordsMatch, validatePassword } from "@/lib/passwordValidation";

type Step = "request" | "verify" | "password" | "done";

function secondsRemaining(ticket: OwnerPasswordResetTicket | null): number {
  if (!ticket) return 0;
  if (ticket.resend_available_at) {
    const ms = new Date(ticket.resend_available_at).getTime() - Date.now();
    return Math.max(0, Math.ceil(ms / 1000));
  }
  return Math.max(0, ticket.retry_after_seconds || 0);
}

function countdownLabel(seconds: number): string {
  const safe = Math.max(0, seconds);
  const minutes = String(Math.floor(safe / 60)).padStart(2, "0");
  const remainder = String(safe % 60).padStart(2, "0");
  return `Resend code in ${minutes}:${remainder}`;
}

function errorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const detail = error.response?.data?.detail;
    if (typeof detail === "string" && detail.trim()) return detail;
    if (detail && typeof detail === "object" && "message" in detail) {
      const message = (detail as { message?: unknown }).message;
      if (typeof message === "string" && message.trim()) return message;
    }
  }
  return "Something went wrong. Please try again.";
}

function ticketFromError(error: unknown): OwnerPasswordResetTicket | null {
  if (!axios.isAxiosError(error) || error.response?.status !== 429) return null;
  const detail = error.response.data?.detail;
  if (!detail || typeof detail !== "object") return null;
  const body = detail as Partial<OwnerPasswordResetTicket>;
  return {
    message: body.message || "Please wait before requesting another code.",
    resend_available_at: body.resend_available_at ?? null,
    retry_after_seconds: body.retry_after_seconds ?? 0,
  };
}

export function OwnerForgotPasswordPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState<Step>("request");
  const [email, setEmail] = useState("");
  const [businessCode, setBusinessCode] = useState("");
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [ticket, setTicket] = useState<OwnerPasswordResetTicket | null>(null);
  const [resetToken, setResetToken] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => Date.now());

  const secondsLeft = secondsRemaining(ticket);
  const passwordErrors = validatePassword(password).errors;
  const normalizedCode = businessCode.trim().toUpperCase().replace(/\s+/g, "");

  useEffect(() => {
    if (secondsLeft <= 0) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [secondsLeft, now]);

  useEffect(() => {
    function onFocus() {
      if (!email.trim() || !normalizedCode || step === "password" || step === "done") return;
      ownerPasswordResetStatus(email.trim(), normalizedCode)
        .then((next) => setTicket(next))
        .catch(() => undefined);
    }
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [email, normalizedCode, step]);

  async function requestCode() {
    if (busy || secondsLeft > 0) return;
    if (!email.trim() || !normalizedCode) {
      setMessage("Enter your registered email and business code.");
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      const next = await requestOwnerPasswordReset(email.trim(), normalizedCode);
      setTicket(next);
      setMessage(next.message);
      setStep("verify");
    } catch (error) {
      const waiting = ticketFromError(error);
      if (waiting) {
        setTicket(waiting);
        setMessage(waiting.message);
        setStep("verify");
      } else {
        setMessage(errorMessage(error));
      }
    } finally {
      setBusy(false);
    }
  }

  async function verifyCode() {
    if (busy || code.trim().length !== 6) return;
    setBusy(true);
    setMessage(null);
    try {
      const result = await verifyOwnerPasswordReset(
        email.trim(),
        normalizedCode,
        code.trim()
      );
      setResetToken(result.reset_token);
      setStep("password");
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  async function savePassword() {
    if (busy || !resetToken || !validatePassword(password).valid) return;
    if (!passwordsMatch(password, confirm)) {
      setMessage("The passwords do not match.");
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      await completeOwnerPasswordReset(resetToken, password);
      setResetToken(null);
      setStep("done");
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  const title =
    step === "request"
      ? "Forgot password"
      : step === "verify"
        ? "Enter verification code"
        : step === "password"
          ? "Create a new password"
          : "Password updated";

  const subtitle =
    step === "request"
      ? "Enter the email registered to your owner account and your business code. We will send a verification code to that email."
      : step === "verify"
        ? "Enter the 6-digit code sent to your registered email. The code expires in 10 minutes."
        : step === "password"
          ? "Choose a new password. You will sign in with your email and business code afterward."
          : "Your password was updated. Sign in with your email, business code, and new password.";

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[minmax(300px,38vw)_1fr]">
      <SystemBrandPanel />
      <main className="flex min-h-screen items-center justify-center px-5 py-8 sm:px-8 lg:px-12">
        <div className="w-full max-w-md">
          <Link
            to="/owner-login"
            className="mb-6 inline-flex items-center gap-2 text-sm font-medium text-[#1E3A5F]"
          >
            <ArrowLeft className="h-4 w-4" />
            Back to sign in
          </Link>
          <div className="mb-8">
            <div className="mb-5 inline-flex items-center gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-xs font-medium text-[#1E3A5F]">
              <BadgeCheck className="h-4 w-4" />
              Owner portal
            </div>
            <h1 className="text-3xl font-semibold tracking-tight text-[#111827] sm:text-4xl">
              {title}
            </h1>
            <p className="mt-3 text-sm leading-6 text-[#6B7280]">{subtitle}</p>
          </div>

          <section className="rounded-3xl border border-white/70 bg-white/75 p-5 shadow-sm backdrop-blur sm:p-7">
            <form
              className="space-y-5"
              onSubmit={(event) => {
                event.preventDefault();
                if (step === "request") void requestCode();
                else if (step === "verify") void verifyCode();
                else if (step === "password") void savePassword();
                else navigate("/owner-login");
              }}
            >
              {(step === "request" || step === "verify") && (
                <>
                  <div className="space-y-2">
                    <Label htmlFor="email">Registered email</Label>
                    <div className="relative">
                      <Mail className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                      <Input
                        id="email"
                        type="email"
                        value={email}
                        onChange={(event) => setEmail(event.target.value)}
                        required
                        readOnly={step !== "request"}
                        className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                      />
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="business_code">Business code</Label>
                    <div className="relative">
                      <Building2 className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                      <Input
                        id="business_code"
                        value={businessCode}
                        onChange={(event) => setBusinessCode(event.target.value)}
                        placeholder="MB-D90987"
                        required
                        readOnly={step !== "request"}
                        className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                      />
                    </div>
                  </div>
                </>
              )}

              {step === "verify" && (
                <div className="space-y-2">
                  <Label htmlFor="code">Verification code</Label>
                  <Input
                    id="code"
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    maxLength={6}
                    value={code}
                    onChange={(event) =>
                      setCode(event.target.value.replace(/\D/g, "").slice(0, 6))
                    }
                    placeholder="6-digit code"
                    className="h-11 rounded-lg border-0 bg-white shadow-sm tracking-[0.3em]"
                  />
                </div>
              )}

              {step === "password" && (
                <>
                  <PasswordInput
                    id="new_password"
                    label="New password"
                    value={password}
                    onChange={setPassword}
                    inputClassName="h-11 rounded-lg border-0 bg-white shadow-sm"
                  />
                  <PasswordInput
                    id="confirm_password"
                    label="Confirm new password"
                    value={confirm}
                    onChange={setConfirm}
                    inputClassName="h-11 rounded-lg border-0 bg-white shadow-sm"
                  />
                  {passwordErrors.length > 0 && (
                    <ul className="space-y-1 text-xs text-[#6B7280]">
                      {passwordErrors.map((error) => (
                        <li key={error}>{error}</li>
                      ))}
                    </ul>
                  )}
                </>
              )}

              {message && <p className="text-sm leading-6 text-[#1F2937]">{message}</p>}

              {(step === "request" || step === "verify") && secondsLeft > 0 && (
                <p className="text-center text-sm font-semibold text-[#6B7280]">
                  {countdownLabel(secondsLeft)}
                </p>
              )}

              {step === "verify" && secondsLeft <= 0 && (
                <Button
                  type="button"
                  variant="ghost"
                  className="w-full"
                  disabled={busy}
                  onClick={() => void requestCode()}
                >
                  Resend code
                </Button>
              )}

              {step === "request" && (
                <Button
                  type="submit"
                  className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white hover:bg-[#284B73]"
                  disabled={busy || secondsLeft > 0}
                >
                  {busy ? "Sending..." : "Send verification code"}
                </Button>
              )}
              {step === "verify" && (
                <Button
                  type="submit"
                  className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white hover:bg-[#284B73]"
                  disabled={busy || code.trim().length !== 6}
                >
                  {busy ? "Verifying..." : "Verify"}
                </Button>
              )}
              {step === "password" && (
                <Button
                  type="submit"
                  className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white hover:bg-[#284B73]"
                  disabled={busy || !validatePassword(password).valid}
                >
                  {busy ? "Saving..." : "Save new password"}
                </Button>
              )}
              {step === "done" && (
                <Button
                  type="submit"
                  className="h-12 w-full rounded-xl bg-[#1E3A5F] text-white hover:bg-[#284B73]"
                >
                  Back to sign in
                </Button>
              )}
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
