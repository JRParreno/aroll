import { useState } from "react";
import { Clock3 } from "lucide-react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import {
  PublicPage,
  publicFieldClass,
  publicPrimaryButtonClass,
} from "@/components/marketing/PublicPage";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getRegistrationByEmail } from "@/lib/api";
import { formatVerificationStatus } from "@/lib/registrationDocuments";

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

  const timeline = data
    ? [
        {
          label: "Submitted",
          done: data.application_status !== "draft",
          current: data.application_status === "draft",
        },
        {
          label: "Under review",
          done: data.application_status === "approved" || data.application_status === "rejected",
          current: data.application_status === "pending",
        },
        {
          label: data.application_status === "rejected" ? "Needs updates" : "Approved",
          done: data.application_status === "approved" || data.application_status === "rejected",
          current: data.application_status === "approved" || data.application_status === "rejected",
        },
      ]
    : [];

  return (
    <PublicPage showLoginLink>
      <div className="mx-auto w-full max-w-4xl">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#93C5FD]">
          Registration
        </p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight text-white sm:text-3xl">
          Track your registration
        </h1>
        <p className="mt-1 max-w-2xl text-sm leading-5 text-[#B7C3D7]">
          Enter the email used for your business application to see its current status.
        </p>

        <div className="mt-3 rounded-2xl bg-white p-4 text-[#172554] shadow-xl shadow-black/25 sm:p-5">
        <form onSubmit={handleCheckStatus} className="grid gap-4 sm:grid-cols-[1fr_auto] sm:items-end">
          <div className="space-y-2">
            <Label htmlFor="track_email">Email Address</Label>
            <Input
              id="track_email"
              type="email"
              placeholder="you@company.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className={publicFieldClass}
            />
          </div>
          <Button type="submit" className={publicPrimaryButtonClass} disabled={isFetching}>
            {isFetching ? "Checking..." : "Check status"}
          </Button>
        </form>

          {isFetched && isError && (
            <section className="mt-4">
              <p className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                No registration found for this email address.
              </p>
              <Button asChild variant="outline" className="mt-4 h-11 rounded-xl border-[#DBEAFE] bg-white">
                <Link to="/register-business">Start Registration</Link>
              </Button>
            </section>
          )}

          {data && (
            <section className="mt-4 border-t border-[#DBEAFE] pt-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="text-xl font-semibold text-[#172554]">{statusTitle}</h2>
                  <p className="mt-1 max-w-xl text-sm leading-6 text-[#475569]">{statusCopy}</p>
                </div>
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

              <ol className="mt-3 flex flex-wrap gap-x-6 gap-y-2">
                {timeline.map((item) => (
                  <li key={item.label} className="flex items-center gap-2 text-sm text-[#172554]">
                    <span
                      className={`h-2.5 w-2.5 rounded-full ${
                        item.done || item.current ? "bg-[#2563EB]" : "bg-[#DBEAFE]"
                      }`}
                      aria-hidden="true"
                    />
                    <span className={item.current ? "font-semibold" : "text-[#475569]"}>
                      {item.label}
                    </span>
                  </li>
                ))}
              </ol>

              <div id="application-details" className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <DetailItem label="Business" value={data.business_name} />
                <DetailItem label="Registration reference" value={data.id} />
                <DetailItem label="Application date" value={formatDateTime(data.submitted_at)} />
                <DetailItem label="Verification status" value={verificationStatus ?? "Not available"} />
              </div>

                {data.application_status === "draft" && (
                  <div className="mt-3">
                    <p className="text-sm text-[#475569]">
                      A registration for{" "}
                      <span className="font-medium text-[#111827]">
                        {data.business_name}
                      </span>{" "}
                      was started but not yet submitted. Continue where you
                      left off.
                    </p>
                    <Button asChild className={`mt-4 w-full ${publicPrimaryButtonClass}`}>
                      <Link to="/register-business">Continue Registration</Link>
                    </Button>
                  </div>
                )}

                {data.application_status === "pending" && (
                  <p className="mt-3 text-sm text-[#475569]">
                    Your application is currently under review. Please wait for
                    administrator verification.
                  </p>
                )}

                {data.application_status === "approved" && (
                  <p className="mt-3 text-sm text-[#475569]">
                    Your application has been approved. You may now log in using
                    the Business Owner Login page.
                  </p>
                )}

                {data.application_status === "rejected" && (
                  <div className="mt-3 space-y-3">
                    <p className="text-sm text-[#475569]">
                      Your application has been rejected.
                    </p>

                    {data.rejection_reason && (
                      <section className="rounded-2xl border border-red-200 bg-red-50/80 p-4">
                        <p className="text-xs font-medium uppercase tracking-wide text-red-800">
                          Rejection Reason
                        </p>
                        <p className="mt-2 whitespace-pre-line text-sm leading-relaxed text-red-700">
                          {data.rejection_reason}
                        </p>
                      </section>
                    )}

                    <DetailItem
                      label="Submission Date"
                      value={formatDateTime(data.submitted_at)}
                    />

                    <Button asChild className={`w-full ${publicPrimaryButtonClass}`}>
                      <Link
                        to={`/rejected-application?email=${encodeURIComponent(searchedEmail)}`}
                      >
                        Resubmit Documents
                      </Link>
                    </Button>
                  </div>
                )}

              <p className="mt-3 max-w-3xl text-sm leading-6 text-[#475569]">
                Our administrator verifies business documents carefully. You will be notified once your account status changes.
              </p>

              <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                <Button asChild variant="outline" className="h-11 rounded-xl border-[#DBEAFE] bg-white">
                  <Link to="/register-business">Back to Registration</Link>
                </Button>
                <Button asChild className={publicPrimaryButtonClass}>
                  <Link to="/owner-login">Go to Login</Link>
                </Button>
              </div>

              {data.application_status === "pending" && (
                <div className="mt-3 flex items-center gap-2 text-sm text-[#475569]">
                  <Clock3 className="h-4 w-4 text-[#6B7280]" />
                  <p>Estimated Review Time: 16 - 48 hours</p>
                </div>
              )}
            </section>
          )}
        </div>
      </div>
    </PublicPage>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-[#475569]">{label}</p>
      <p className="mt-1 text-sm text-[#172554]">{value}</p>
    </div>
  );
}
