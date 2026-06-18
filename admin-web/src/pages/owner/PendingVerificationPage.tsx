import { useQuery } from "@tanstack/react-query";
import { Link, Navigate, useSearchParams } from "react-router-dom";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getRegistrationByEmail } from "@/lib/api";
import { DOCUMENT_LABELS } from "@/lib/registrationDocuments";

function formatApplicationStatus(status: string) {
  if (status === "pending") return "Pending Verification";
  return status.replace(/_/g, " ");
}
export function PendingVerificationPage() {
  const [searchParams] = useSearchParams();
  const email = searchParams.get("email")?.trim() ?? "";

  const { data, isLoading, isError } = useQuery({
    queryKey: ["registration-by-email", email],
    queryFn: () => getRegistrationByEmail(email),
    enabled: email.length > 0,
    retry: false,
  });

  if (email && data?.application_status === "rejected") {
    return (
      <Navigate
        to={`/rejected-application?email=${encodeURIComponent(email)}`}
        replace
      />
    );
  }

  return (
    <div className="min-h-screen bg-muted/30 p-4 sm:p-6">
      <div className="mx-auto flex max-w-xl flex-col gap-6">
        <div>
          <h1 className="text-2xl font-semibold">Application Status</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Track your business registration while our team reviews your
            application.
          </p>
        </div>

        {!email && (
          <Card>
            <CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">
                No email address provided. Return to registration to check your
                application status.
              </p>
              <Button asChild className="mt-4" variant="outline">
                <Link to="/register-business">Back to Registration</Link>
              </Button>
            </CardContent>
          </Card>
        )}

        {email && isLoading && (
          <Card>
            <CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">
                Loading application details…
              </p>
            </CardContent>
          </Card>
        )}

        {email && isError && (
          <Card>
            <CardContent className="pt-6 space-y-4">
              <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
                No registration application found for this email address.
              </p>
              <Button asChild variant="outline">
                <Link to="/register-business">Start Registration</Link>
              </Button>
            </CardContent>
          </Card>
        )}

        {data && (
          <Card className="border-primary/30">
            <CardHeader className="space-y-3">
              <CardTitle className="text-xl">{data.business_name}</CardTitle>
              <StatusBadge status={formatApplicationStatus(data.application_status)} />
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
                    Status
                  </p>
                  <p className="mt-1 text-sm">
                    {formatApplicationStatus(data.application_status)}
                  </p>
                </div>
              </div>

              <div>
                <p className="mb-3 text-sm font-medium">Submitted Documents</p>
                {data.documents.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    No documents on file yet.
                  </p>
                ) : (
                  <ul className="divide-y rounded-md border text-sm">
                    {data.documents.map((doc) => (
                      <li
                        key={doc.id}
                        className="flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
                      >
                        <div>
                          <p className="font-medium">
                            {DOCUMENT_LABELS[doc.document_type] ??
                              doc.document_type}
                          </p>
                          <p className="text-muted-foreground">
                            {doc.original_filename}
                          </p>
                        </div>
                        <p className="text-xs text-muted-foreground">
                          {formatDateTime(doc.uploaded_at)}
                        </p>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              <p className="text-sm text-muted-foreground">
                Our team will review your documents and contact you at{" "}
                <span className="text-foreground">{data.owner_email}</span> once
                your business has been approved.
              </p>

              <Button asChild variant="outline">
                <Link to="/owner-login">Back to Owner Login</Link>
              </Button>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
