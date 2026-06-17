import { useState } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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

  return (
    <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
      <div className="mx-auto flex max-w-xl flex-col gap-6">
        <div>
          <h1 className="text-2xl font-semibold">Track Registration</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Check the status of your business registration application.
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Email Address</CardTitle>
            <p className="text-sm text-muted-foreground">
              Enter the email you used when registering your business.
            </p>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleCheckStatus} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="track_email">Email Address</Label>
                <Input
                  id="track_email"
                  type="email"
                  placeholder="Enter the email used during registration"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
              <Button type="submit" className="w-full" disabled={isFetching}>
                {isFetching ? "Checking…" : "Check Status"}
              </Button>
            </form>
          </CardContent>
        </Card>

        {isFetched && isError && (
          <Card>
            <CardContent className="pt-6 space-y-4">
              <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                No registration found for this email address.
              </p>
              <Button asChild variant="outline">
                <Link to="/register-business">Start Registration</Link>
              </Button>
            </CardContent>
          </Card>
        )}

        {data && data.application_status === "draft" && (
          <Card>
            <CardContent className="space-y-4 pt-6">
              <p className="text-sm text-muted-foreground">
                A registration for <span className="font-medium text-foreground">{data.business_name}</span> was
                started but not yet submitted. Continue where you left off.
              </p>
              <Button asChild className="w-full">
                <Link to="/register-business">Continue Registration</Link>
              </Button>
            </CardContent>
          </Card>
        )}

        {data && data.application_status === "pending" && (
          <Card className="border-primary/30">
            <CardHeader className="space-y-3">
              <CardTitle className="text-xl">{data.business_name}</CardTitle>
              <StatusBadge status="Pending Verification" />
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Application Date
                  </p>
                  <p className="mt-1 text-sm">
                    {formatDateTime(data.submitted_at)}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Verification Status
                  </p>
                  <p className="mt-1 text-sm">{verificationStatus}</p>
                </div>
              </div>

              <p className="text-sm text-muted-foreground">
                Your application is currently under review. Please wait for
                administrator verification.
              </p>

              <Button asChild variant="outline" className="w-full">
                <Link to="/register-business">Back to Registration</Link>
              </Button>
            </CardContent>
          </Card>
        )}

        {data && data.application_status === "approved" && (
          <Card className="border-emerald-200">
            <CardHeader className="space-y-3">
              <CardTitle className="text-xl">{data.business_name}</CardTitle>
              <StatusBadge status="Approved" />
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Application Date
                  </p>
                  <p className="mt-1 text-sm">
                    {formatDateTime(data.submitted_at)}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Verification Status
                  </p>
                  <p className="mt-1 text-sm">{verificationStatus}</p>
                </div>
              </div>

              <p className="text-sm text-muted-foreground">
                Your application has been approved. You may now log in using the
                Business Owner Login page.
              </p>

              <Button asChild className="w-full">
                <Link to="/owner-login">Go to Business Owner Login</Link>
              </Button>
            </CardContent>
          </Card>
        )}

        {data && data.application_status === "rejected" && (
          <Card className="border-red-200">
            <CardHeader className="space-y-3">
              <CardTitle className="text-xl">{data.business_name}</CardTitle>
              <StatusBadge status="Rejected" />
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Application Date
                  </p>
                  <p className="mt-1 text-sm">
                    {formatDateTime(data.submitted_at)}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Verification Status
                  </p>
                  <p className="mt-1 text-sm">{verificationStatus}</p>
                </div>
              </div>

              <p className="text-sm text-muted-foreground">
                Your application has been rejected.
              </p>

              {data.rejection_reason && (
                <section className="rounded-lg border border-red-200 bg-red-50/80 p-4">
                  <p className="text-xs font-medium uppercase tracking-wide text-red-800">
                    Rejection Reason
                  </p>
                  <p className="mt-2 text-sm leading-relaxed text-red-700">
                    {data.rejection_reason}
                  </p>
                </section>
              )}

              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Submission Date
                </p>
                <p className="mt-1 text-sm">
                  {formatDateTime(data.submitted_at)}
                </p>
              </div>

              <Button asChild className="w-full">
                <Link
                  to={`/rejected-application?email=${encodeURIComponent(searchedEmail)}`}
                >
                  Resubmit Documents
                </Link>
              </Button>
            </CardContent>
          </Card>
        )}

        <p className="text-center text-sm text-muted-foreground">
          <Link to="/register-business" className="underline underline-offset-2">
            Back to Registration
          </Link>
        </p>
      </div>
    </div>
  );
}
