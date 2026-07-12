import { useState } from "react";
import { ArrowLeft, CheckCircle2, Clock3, Search } from "lucide-react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { SystemBrandPanel } from "@/components/branding/SystemBranding";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getRegistrationByEmail } from "@/lib/api";
import { formatVerificationStatus } from "@/lib/registrationDocuments";

function StatusIllustration() {
  return (
    <div className="relative mx-auto my-5 h-48 w-56">
      <div className="absolute left-7 top-3 h-28 w-24 -rotate-12 rounded-xl border-4 border-[#111827] bg-white shadow-sm" />
      <div className="absolute left-20 top-8 h-32 w-28 rounded-xl border-4 border-[#111827] bg-white shadow-md">
        <div className="mx-auto mt-7 h-3 w-16 rounded-full bg-[#111827]" />
        <div className="mx-auto mt-5 h-2 w-20 rounded-full bg-[#111827]/80" />
        <div className="mx-auto mt-4 h-2 w-16 rounded-full bg-[#111827]/80" />
      </div>
      <div className="absolute bottom-5 left-12 h-28 w-36 rounded-2xl border-4 border-[#111827] bg-white shadow-sm" />
      <div className="absolute bottom-8 left-20 h-2 w-24 rounded-full bg-[#111827]" />
      <div className="absolute bottom-2 right-4 flex h-16 w-16 items-center justify-center rounded-full border-4 border-[#111827] bg-white">
        <CheckCircle2 className="h-10 w-10 text-[#111827]" strokeWidth={3} />
      </div>
    </div>
  );
}

export function TrackRegistrationPage() {
  const [email, setEmail] = useState("");
  const [searchedEmail, setSearchedEmail] = useState("");

  const { data, isFetching, isError, isFetched } = useQuery({
    queryKey: ["registration-by-email", searchedEmail],
    queryFn: () => getRegistrationByEmail(searchedEmail),
    enabled: searchedEmail.length > 0,
    retry: false,
  });

  function handleCheckStatus(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = email.trim();
    if (!trimmed) return;
    setSearchedEmail(trimmed);
  }

  const verificationStatus = data
    ? formatVerificationStatus(data.application_status)
    : null;

  const statusTitle =
    data?.application_status === "approved"
      ? "Application Approved!"
      : data?.application_status === "rejected"
        ? "Application Needs Updates"
        : data?.application_status === "draft"
          ? "Application Draft"
          : "Application Submitted!";

  const statusCopy =
    data?.application_status === "approved"
      ? "Your company registration has been approved and your owner account is ready."
      : data?.application_status === "rejected"
        ? "Your application was reviewed and needs updated documents before approval."
        : data?.application_status === "draft"
          ? "Your registration was started but has not been submitted yet."
          : "Your company registration has been received and is now under review.";

  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827] lg:grid lg:grid-cols-[1fr_minmax(300px,42vw)]">
      <main className="flex min-h-screen items-center justify-center px-5 py-8 sm:px-8 lg:px-12">
        <div className="w-full max-w-3xl">
          <div className="mb-7 flex items-center gap-5">
            <Button
              asChild
              variant="ghost"
              size="icon"
              className="h-11 w-11 rounded-full text-[#111827] hover:bg-white"
            >
              <Link to="/owner-login" aria-label="Back to login">
                <ArrowLeft className="h-6 w-6" />
              </Link>
            </Button>
            <h1 className="text-3xl font-semibold tracking-tight text-[#111827] sm:text-4xl">
              Registration Status
            </h1>
          </div>

          <section className="rounded-3xl border border-white/70 bg-white/70 p-5 shadow-sm backdrop-blur sm:p-7">
            <form
              onSubmit={handleCheckStatus}
              className="grid gap-4 md:grid-cols-[1fr_auto]"
            >
              <div className="space-y-2">
                <Label htmlFor="track_email">Email Address</Label>
                <div className="relative">
                  <Search className="absolute left-3 top-3.5 h-4 w-4 text-[#9CA3AF]" />
                  <Input
                    id="track_email"
                    type="email"
                    placeholder="Enter the email used during registration"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    className="h-11 rounded-lg border-0 bg-white pl-10 shadow-sm"
                  />
                </div>
              </div>
              <Button
                type="submit"
                className="h-11 self-end rounded-xl bg-[#1E3A5F] px-8 text-white shadow-sm hover:bg-[#284B73]"
                disabled={isFetching}
              >
                {isFetching ? "Checking..." : "Check Status"}
              </Button>
            </form>
          </section>

          {isFetched && isError && (
            <section className="mt-5 rounded-3xl border border-red-100 bg-white p-6 shadow-sm">
              <p className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                No registration found for this email address.
              </p>
              <Button
                asChild
                variant="outline"
                className="mt-4 h-11 rounded-xl border-slate-200 bg-white"
              >
                <Link to="/register-business">Start Registration</Link>
              </Button>
            </section>
          )}

          {data && (
            <section className="mt-5 rounded-3xl border border-white/70 bg-white/80 p-6 text-center shadow-sm backdrop-blur sm:p-8">
              <h2 className="text-2xl font-semibold text-[#111827]">
                {statusTitle}
              </h2>
              <div className="mt-4 flex justify-center">
                <StatusBadge
                  status={
                    data.application_status === "approved"
                      ? "Approved"
                      : data.application_status === "rejected"
                        ? "Rejected"
                        : data.application_status === "draft"
                          ? "Draft"
                          : "Pending Verification"
                  }
                />
              </div>

              <p className="mx-auto mt-5 max-w-md text-base font-medium leading-6 text-[#6B7280]">
                {statusCopy}
              </p>

              <StatusIllustration />

              <div
                id="application-details"
                className="mx-auto mt-5 max-w-2xl rounded-3xl border border-slate-200 bg-white p-5 text-left shadow-sm sm:p-6"
              >
                <div className="mb-5 text-center">
                  <h3 className="text-lg font-semibold text-[#111827]">
                    {data.business_name}
                  </h3>
                  <p className="text-sm text-[#6B7280]">
                    {verificationStatus}
                  </p>
                </div>

                <div className="grid gap-4 sm:grid-cols-2">
                  <DetailItem
                    label="Application Date"
                    value={formatDateTime(data.submitted_at)}
                  />
                  <DetailItem
                    label="Verification Status"
                    value={verificationStatus ?? "Not available"}
                  />
                </div>

                {data.application_status === "draft" && (
                  <div className="mt-5">
                    <p className="text-sm text-[#6B7280]">
                      A registration for{" "}
                      <span className="font-medium text-[#111827]">
                        {data.business_name}
                      </span>{" "}
                      was started but not yet submitted. Continue where you
                      left off.
                    </p>
                    <Button asChild className="mt-4 h-11 w-full rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]">
                      <Link to="/register-business">Continue Registration</Link>
                    </Button>
                  </div>
                )}

                {data.application_status === "pending" && (
                  <p className="mt-5 text-sm text-[#6B7280]">
                    Your application is currently under review. Please wait for
                    administrator verification.
                  </p>
                )}

                {data.application_status === "approved" && (
                  <p className="mt-5 text-sm text-[#6B7280]">
                    Your application has been approved. You may now log in using
                    the Business Owner Login page.
                  </p>
                )}

                {data.application_status === "rejected" && (
                  <div className="mt-5 space-y-5">
                    <p className="text-sm text-[#6B7280]">
                      Your application has been rejected.
                    </p>

                    {data.rejection_reason && (
                      <section className="rounded-2xl border border-red-200 bg-red-50/80 p-4">
                        <p className="text-xs font-medium uppercase tracking-wide text-red-800">
                          Rejection Reason
                        </p>
                        <p className="mt-2 text-sm leading-relaxed text-red-700">
                          {data.rejection_reason}
                        </p>
                      </section>
                    )}

                    <DetailItem
                      label="Submission Date"
                      value={formatDateTime(data.submitted_at)}
                    />

                    <Button asChild className="h-11 w-full rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]">
                      <Link
                        to={`/rejected-application?email=${encodeURIComponent(searchedEmail)}`}
                      >
                        Resubmit Documents
                      </Link>
                    </Button>
                  </div>
                )}
              </div>

              <p className="mx-auto mt-5 max-w-md text-xs leading-5 text-[#6B7280]">
                Our administrator verifies business documents carefully. You
                will be notified once your account status changes.
              </p>

              <div className="mx-auto mt-6 grid max-w-2xl gap-3 sm:grid-cols-2">
                <Button
                  asChild
                  variant="outline"
                  className="h-11 rounded-xl border-slate-200 bg-[#DBEAFE] text-[#111827] hover:bg-[#CFE2F7]"
                >
                  <Link to="/register-business">Back to Registration</Link>
                </Button>
                <Button
                  asChild
                  className="h-11 rounded-xl bg-[#1E3A5F] text-white shadow-sm hover:bg-[#284B73]"
                >
                  <Link to="/owner-login">Go to Login</Link>
                </Button>
              </div>

              {data.application_status === "pending" && (
                <div className="mt-6 flex flex-col items-center gap-2 text-xs font-medium text-[#6B7280]">
                  <Clock3 className="h-8 w-8 text-[#6B7280]" />
                  <p>Estimated Review Time: 16 - 48 hours</p>
                </div>
              )}
            </section>
          )}

          <p className="mt-6 text-center text-sm text-[#6B7280]">
            <Link
              to="/register-business"
              className="font-medium text-[#1E3A5F] underline underline-offset-2"
            >
              Back to Registration
            </Link>
          </p>
        </div>
      </main>

      <SystemBrandPanel />
    </div>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-[#6B7280]">
        {label}
      </p>
      <p className="mt-1 text-sm text-[#111827]">{value}</p>
    </div>
  );
}
