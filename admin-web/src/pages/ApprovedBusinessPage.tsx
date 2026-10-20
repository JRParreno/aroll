import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom";
import {
  Building2,
  ChevronRight,
  Mail,
  MapPin,
  Users,
} from "lucide-react";
import { toast } from "sonner";
import {
  AdminPage,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import { formatDateTime, StatusBadge } from "@/components/detail/DetailLayout";
import { TenantKindBadge } from "@/components/tenant/SimulatedBadge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  listBusinesses,
  sendRegistrationApprovalEmail,
  type BusinessListItem,
} from "@/lib/api";

type DirectoryView = "all" | "recent" | "email-pending";

function toIsoDate(value: Date) {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function recentDateRange() {
  const to = new Date();
  const from = new Date();
  from.setDate(from.getDate() - 29);
  return { from: toIsoDate(from), to: toIsoDate(to) };
}

function parseView(value: string | null): DirectoryView {
  if (value === "recent" || value === "email-pending") return value;
  return "all";
}

function emailStatusLabel(status: string | null | undefined) {
  if (status === "sent") return "Sent";
  if (status === "failed") return "Failed";
  if (status === "sending") return "Sending";
  if (status === "not_sent") return "Not Sent";
  return "Unknown";
}

function emailStatusClass(status: string | null | undefined) {
  if (status === "sent") return "bg-emerald-50 text-emerald-700";
  if (status === "failed") return "bg-red-50 text-red-700";
  if (status === "sending") return "bg-amber-50 text-amber-700";
  return "bg-slate-100 text-[#4B5563]";
}

function canSendOwnerLoginEmail(business: BusinessListItem) {
  return Boolean(
    business.registration_id && business.approval_email_status !== "sent"
  );
}

export function ApprovedBusinessPage() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams, setSearchParams] = useSearchParams();
  const view: DirectoryView = location.pathname.endsWith("/recently-approved")
    ? "recent"
    : parseView(searchParams.get("view"));
  const appliedFrom = searchParams.get("from") ?? "";
  const appliedTo = searchParams.get("to") ?? "";
  const [fromDate, setFromDate] = useState(appliedFrom);
  const [toDate, setToDate] = useState(appliedTo);
  const [rangeError, setRangeError] = useState("");
  const [sendingId, setSendingId] = useState<string | null>(null);

  const recentDefaults = useMemo(() => recentDateRange(), []);
  const queryFrom =
    appliedFrom || (view === "recent" ? recentDefaults.from : "");
  const queryTo = appliedTo || (view === "recent" ? recentDefaults.to : "");

  const listParams = useMemo(() => {
    const params: {
      approved_from?: string;
      approved_to?: string;
      email_status?: "pending";
    } = {};
    if (queryFrom) params.approved_from = queryFrom;
    if (queryTo) params.approved_to = queryTo;
    if (view === "email-pending") params.email_status = "pending";
    return params;
  }, [queryFrom, queryTo, view]);

  const { data = [], isLoading } = useQuery({
    queryKey: ["businesses", view, queryFrom, queryTo],
    queryFn: () => listBusinesses(listParams),
  });

  const sendEmail = useMutation({
    mutationFn: (registrationId: string) =>
      sendRegistrationApprovalEmail(registrationId),
    onSuccess: (res, registrationId) => {
      toast.success(`Login instructions sent to ${res.recipient}`);
      setSendingId(null);
      qc.setQueryData<BusinessListItem[]>(
        ["businesses", view, queryFrom, queryTo],
        (current) =>
          current?.map((row) =>
            row.registration_id === registrationId
              ? { ...row, approval_email_status: "sent" }
              : row
          )
      );
      qc.invalidateQueries({ queryKey: ["businesses"] });
    },
    onError: (error: unknown) => {
      setSendingId(null);
      const detail =
        error &&
        typeof error === "object" &&
        "response" in error &&
        error.response &&
        typeof error.response === "object" &&
        "data" in error.response &&
        error.response.data &&
        typeof error.response.data === "object" &&
        "detail" in error.response.data
          ? String((error.response.data as { detail: unknown }).detail)
          : "Could not send the login email.";
      toast.error(detail);
      qc.invalidateQueries({ queryKey: ["businesses"] });
    },
  });

  function setView(next: DirectoryView) {
    const params = new URLSearchParams(searchParams);
    if (next === "all") params.delete("view");
    else params.set("view", next);
    const query = params.toString();
    if (next === "recent") {
      navigate(`/admin/recently-approved${query ? `?${query}` : ""}`);
      return;
    }
    navigate(`/admin/approved-business${query ? `?${query}` : ""}`);
  }

  function applyFilter() {
    if (fromDate && toDate && toDate < fromDate) {
      setRangeError("End date cannot be earlier than start date.");
      return;
    }
    setRangeError("");
    const params = new URLSearchParams(searchParams);
    if (fromDate) params.set("from", fromDate);
    else params.delete("from");
    if (toDate) params.set("to", toDate);
    else params.delete("to");
    setSearchParams(params);
  }

  function clearFilter() {
    setFromDate("");
    setToDate("");
    setRangeError("");
    const params = new URLSearchParams(searchParams);
    params.delete("from");
    params.delete("to");
    setSearchParams(params);
  }

  const visibleRows =
    view === "email-pending"
      ? data.filter((row) => row.approval_email_status !== "sent")
      : data;

  const title =
    view === "recent"
      ? "Recently Approved"
      : view === "email-pending"
        ? "Owner Login Email Pending"
        : "Approved Businesses";
  const description =
    view === "recent"
      ? "Businesses approved in the last 30 days, newest first. Adjust the dates to change the period."
      : view === "email-pending"
        ? "Approved businesses whose Owner Login email has not been successfully sent."
        : "Browse approved businesses on the platform and open a profile to review owner, employee, and location details.";

  return (
    <AdminPage>
      <AdminPageHeader
        eyebrow="Business directory"
        title={title}
        description={description}
      />

      <AdminPageContent>
        <div className="flex flex-wrap gap-2">
          {(
            [
              ["all", "All businesses"],
              ["recent", "Recently Approved"],
              ["email-pending", "Owner Login Email Pending"],
            ] as const
          ).map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => setView(key)}
              className={`rounded-full px-4 py-2 text-sm font-medium transition ${
                view === key
                  ? "bg-[#1E3A5F] text-white"
                  : "bg-white text-[#1F2937] ring-1 ring-[#E8EEF5] hover:bg-[#FAFBFC]"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <Card className="admin-card overflow-hidden rounded-[1.25rem] border-[#E8EEF5] bg-white shadow-none">
          <CardHeader className="border-b border-slate-200 bg-[#FAFBFC] p-5 sm:p-6">
            <div className="flex flex-col gap-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <CardTitle className="text-base font-semibold text-[#1F2937]">
                    Business List
                  </CardTitle>
                  <p className="mt-1 text-sm text-[#6B7280]">
                    {isLoading
                      ? "Loading approved businesses..."
                      : `${visibleRows.length} business${visibleRows.length === 1 ? "" : "es"} found`}
                  </p>
                </div>
                <span className="rounded-full bg-[#EAF2FB] px-3 py-1 text-xs font-medium text-[#1E3A5F]">
                  {view === "email-pending" ? "Email pending" : "Approved"}
                </span>
              </div>

              <div className="grid gap-3 md:grid-cols-[1fr_1fr_auto_auto] md:items-end">
                <div className="space-y-1.5">
                  <Label htmlFor="approved-from">From date</Label>
                  <Input
                    id="approved-from"
                    type="date"
                    value={fromDate}
                    max={toDate || undefined}
                    onChange={(event) => {
                      setFromDate(event.target.value);
                      setRangeError("");
                    }}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="approved-to">To date</Label>
                  <Input
                    id="approved-to"
                    type="date"
                    value={toDate}
                    min={fromDate || undefined}
                    onChange={(event) => {
                      setToDate(event.target.value);
                      setRangeError("");
                    }}
                  />
                </div>
                <Button type="button" onClick={applyFilter}>
                  Apply Filter
                </Button>
                <Button type="button" variant="outline" onClick={clearFilter}>
                  Reset Filter
                </Button>
              </div>
              {rangeError ? (
                <p className="text-sm text-red-600">{rangeError}</p>
              ) : (
                <p className="text-xs text-[#6B7280]">
                  Filters use the actual approval date. Recently Approved defaults
                  to the last 30 days until you apply different dates.
                </p>
              )}
            </div>
          </CardHeader>

          <CardContent className="p-0">
            {isLoading && (
              <div className="divide-y divide-slate-100">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="animate-pulse p-5">
                    <div className="h-4 w-52 rounded bg-slate-200" />
                    <div className="mt-3 h-3 w-72 rounded bg-slate-100" />
                  </div>
                ))}
              </div>
            )}

            {!isLoading && visibleRows.length === 0 && (
              <div className="px-6 py-14 text-center">
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#EAF2FB] text-[#1E3A5F]">
                  <Building2 className="h-6 w-6" />
                </div>
                <p className="mt-4 font-medium text-[#1F2937]">
                  {view === "email-pending"
                    ? "No pending Owner Login emails"
                    : queryFrom || queryTo
                      ? "No businesses match the selected dates"
                      : "No businesses yet"}
                </p>
                <p className="mt-1 text-sm text-[#6B7280]">
                  {view === "email-pending"
                    ? "Businesses appear here after approval until their login email is sent."
                    : queryFrom || queryTo
                      ? "Try a different date range or reset the filter."
                      : "Approved registrations will appear here."}
                </p>
              </div>
            )}

            {!isLoading && visibleRows.length > 0 && (
              <div>
                <div className="hidden grid-cols-[1.1fr_0.9fr_0.7fr_0.6fr_auto] gap-4 border-b border-slate-200 bg-white px-5 py-3 text-xs font-medium uppercase tracking-wide text-[#6B7280] lg:grid">
                  <span>Business</span>
                  <span>Owner / usage</span>
                  <span>Approved</span>
                  <span>Login email</span>
                  <span className="text-right">Action</span>
                </div>

                <div className="divide-y divide-slate-100">
                  {visibleRows.map((business) => {
                    const sendingThis =
                      sendingId === business.registration_id &&
                      sendEmail.isPending;
                    return (
                      <div
                        key={business.id}
                        className="grid gap-4 p-5 md:items-center lg:grid-cols-[1.1fr_0.9fr_0.7fr_0.6fr_auto]"
                      >
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <p className="truncate font-medium text-[#1F2937]">
                              {business.name}
                            </p>
                            <StatusBadge status={business.status} />
                            <TenantKindBadge
                              isDemo={business.is_demo}
                              isInternalTest={business.is_internal_test}
                            />
                          </div>
                          <p className="mt-1 font-mono text-sm text-[#6B7280]">
                            {business.business_code}
                          </p>
                        </div>

                        <div className="space-y-1 text-sm text-[#6B7280]">
                          <p>{business.owner_email || "Owner email unavailable"}</p>
                          <span className="inline-flex items-center gap-1.5">
                            <Users className="h-4 w-4" />
                            {business.employee_count} employees
                          </span>
                          <span className="ml-3 inline-flex items-center gap-1.5">
                            <MapPin className="h-4 w-4" />
                            {business.location_count} location
                            {business.location_count === 1 ? "" : "s"}
                          </span>
                        </div>

                        <p className="text-sm text-[#6B7280]">
                          {business.approved_at
                            ? formatDateTime(business.approved_at)
                            : "Unknown"}
                        </p>

                        <span
                          className={`inline-flex w-fit rounded-full px-2.5 py-1 text-xs font-medium ${emailStatusClass(business.approval_email_status)}`}
                        >
                          {emailStatusLabel(business.approval_email_status)}
                        </span>

                        <div className="flex flex-wrap items-center justify-end gap-2">
                          {canSendOwnerLoginEmail(business) && (
                            <Button
                              type="button"
                              size="sm"
                              variant="outline"
                              disabled={sendingThis}
                              onClick={() => {
                                if (!business.registration_id) return;
                                setSendingId(business.registration_id);
                                sendEmail.mutate(business.registration_id);
                              }}
                            >
                              <Mail className="mr-1.5 h-4 w-4" />
                              {sendingThis ? "Sending…" : "Send login email"}
                            </Button>
                          )}
                          <Link
                            to={`/admin/approved-business/${business.id}`}
                            className="inline-flex items-center justify-between gap-2 rounded-full bg-[#EAF2FB] px-4 py-2 text-sm font-medium text-[#1E3A5F] transition hover:bg-[#D9EAFB]"
                          >
                            View Profile
                            <ChevronRight className="h-4 w-4" />
                          </Link>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </AdminPageContent>
    </AdminPage>
  );
}
