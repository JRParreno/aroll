import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import {
  Building2,
  CalendarClock,
  CheckCircle2,
  Clock,
  FileText,
  Mail,
  MapPin,
  Phone,
  User,
  XCircle,
} from "lucide-react";
import { toast } from "sonner";
import {
  DetailField,
  DetailSection,
  EmptyState,
  formatDateTime,
  PageHeader,
  StatusBadge,
} from "@/components/detail/DetailLayout";
import { Button } from "@/components/ui/button";
import { RegistrationDocumentsSection } from "@/components/registration/RegistrationDocumentsSection";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  approveRegistration,
  getRegistration,
  rejectRegistration,
  sendRegistrationApprovalEmail,
} from "@/lib/api";
import { formatBusinessType } from "@/lib/registrationDocuments";
import {
  OTHER_REJECTION_REASON_ID,
  REGISTRATION_REJECTION_REASONS,
  buildRejectionPayload,
  canConfirmRejection,
  toggleRejectionReason,
} from "@/lib/registrationRejectionReasons";

export function RegistrationDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [rejectOpen, setRejectOpen] = useState(false);
  const [selectedReasons, setSelectedReasons] = useState<string[]>([]);
  const [otherExplanation, setOtherExplanation] = useState("");
  const [emailDialog, setEmailDialog] = useState<{
    businessName: string;
    ownerEmail: string;
    navigateOnClose: boolean;
  } | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["registration", id],
    queryFn: () => getRegistration(id!),
    enabled: Boolean(id),
  });

  const approve = useMutation({
    mutationFn: () => approveRegistration(id!),
    onSuccess: (res: { business_code: string; owner_email: string }) => {
      toast.success(`Approved. Business code: ${res.business_code}`);
      qc.invalidateQueries({ queryKey: ["registrations"] });
      qc.invalidateQueries({ queryKey: ["businesses"] });
      qc.invalidateQueries({ queryKey: ["registration", id] });
      setEmailDialog({
        businessName: data?.business_name ?? "this business",
        ownerEmail: res.owner_email,
        navigateOnClose: true,
      });
    },
    onError: () => toast.error("Approval failed"),
  });

  const sendEmail = useMutation({
    mutationFn: () => sendRegistrationApprovalEmail(id!),
    onSuccess: (res) => {
      toast.success(`Login instructions sent to ${res.recipient}`);
      const shouldNavigate = emailDialog?.navigateOnClose === true;
      setEmailDialog(null);
      if (shouldNavigate) {
        navigate("/admin/registrations");
      }
    },
    onError: (error: unknown) => {
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
          : "Could not send the login email. Approval is unchanged.";
      toast.error(detail);
    },
  });

  function closeEmailDialog() {
    const shouldNavigate = emailDialog?.navigateOnClose === true;
    setEmailDialog(null);
    if (shouldNavigate) {
      navigate("/admin/registrations");
    }
  }

  const reject = useMutation({
    mutationFn: () =>
      rejectRegistration(id!, buildRejectionPayload(selectedReasons, otherExplanation)),
    onSuccess: (res) => {
      if (res.email_status === "sent") {
        toast.success(
          res.recipient
            ? `Registration rejected. The owner was notified at ${res.recipient}.`
            : "Registration rejected. The owner was notified."
        );
      } else {
        toast.success("Registration rejected");
        toast.error(
          res.email_error ||
            "The rejection email could not be sent. The application remains rejected."
        );
      }
      qc.invalidateQueries({ queryKey: ["registrations"] });
      qc.invalidateQueries({ queryKey: ["registration", id] });
      setRejectOpen(false);
      setSelectedReasons([]);
      setOtherExplanation("");
    },
    onError: () => toast.error("Rejection failed"),
  });

  if (isLoading) {
    return (
      <div className="p-6">
        <div className="animate-pulse space-y-4">
          <div className="h-4 w-32 rounded bg-muted" />
          <div className="h-8 w-64 rounded bg-muted" />
          <div className="h-40 rounded-xl bg-muted" />
        </div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-6">
        <EmptyState
          title="Registration not found"
          description="This request may have been removed or the link is invalid."
        />
        <div className="mt-4">
          <Button asChild variant="outline">
            <Link to="/admin/registrations">Back to pending requests</Link>
          </Button>
        </div>
      </div>
    );
  }

  const isPending = data.status === "pending";

  return (
    <div className="p-6 pb-24">
      <div className="mx-auto max-w-4xl space-y-6">
        <PageHeader
          backTo="/admin/registrations"
          backLabel="Pending requests"
          title={data.business_name}
          description="Review the submitted business details before approving or rejecting this registration."
          badge={<StatusBadge status={data.status} />}
          actions={
            isPending ? (
              <>
                <Button
                  onClick={() => approve.mutate()}
                  disabled={approve.isPending || reject.isPending}
                >
                  <CheckCircle2 className="mr-2 h-4 w-4" />
                  Approve
                </Button>
                <Button
                  variant="destructive"
                  onClick={() => setRejectOpen(true)}
                  disabled={approve.isPending || reject.isPending}
                >
                  <XCircle className="mr-2 h-4 w-4" />
                  Reject
                </Button>
              </>
            ) : data.status === "approved" ||
              data.application_status === "approved" ? (
              <Button
                type="button"
                variant="outline"
                onClick={() =>
                  setEmailDialog({
                    businessName: data.business_name,
                    ownerEmail: data.owner_email,
                    navigateOnClose: false,
                  })
                }
              >
                <Mail className="mr-2 h-4 w-4" />
                Send login email
              </Button>
            ) : undefined
          }
        />

        <div className="grid gap-6 lg:grid-cols-3">
          <div className="space-y-6 lg:col-span-2">
            <DetailSection
              title="Business Information"
              description="Details provided during registration."
              icon={<Building2 className="h-4 w-4" />}
            >
              <DetailField
                label="Business Name"
                value={data.business_name}
                icon={<Building2 className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Business Type"
                value={formatBusinessType(data.business_type)}
                icon={<Building2 className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Proposed Address"
                value={data.proposed_address || "Not provided"}
                icon={<MapPin className="h-3.5 w-3.5" />}
                className="sm:col-span-2"
              />
            </DetailSection>

            <DetailSection
              title="Owner Contact"
              description="Primary contact for this business account."
              icon={<User className="h-4 w-4" />}
            >
              <DetailField
                label="Full Name"
                value={data.owner_name}
                icon={<User className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Email"
                value={
                  <a
                    href={`mailto:${data.owner_email}`}
                    className="text-primary hover:underline"
                  >
                    {data.owner_email}
                  </a>
                }
                icon={<Mail className="h-3.5 w-3.5" />}
              />
              <DetailField
                label="Phone"
                value={
                  data.owner_phone ? (
                    <a
                      href={`tel:${data.owner_phone}`}
                      className="text-primary hover:underline"
                    >
                      {data.owner_phone}
                    </a>
                  ) : (
                    "Not provided"
                  )
                }
                icon={<Phone className="h-3.5 w-3.5" />}
              />
            </DetailSection>

            <DetailSection
              title="Uploaded Documents"
              description="Review submitted verification files."
              icon={<FileText className="h-4 w-4" />}
            >
              <div className="sm:col-span-2">
                <RegistrationDocumentsSection
                  registrationId={data.id}
                  documents={data.documents}
                />
              </div>
            </DetailSection>
          </div>

          <div className="space-y-6">
            <DetailSection
              title="Timeline"
              description="Key dates for this request."
              icon={<CalendarClock className="h-4 w-4" />}
            >
              <DetailField
                label="Submitted"
                value={formatDateTime(data.submitted_at)}
                icon={<Clock className="h-3.5 w-3.5" />}
                className="sm:col-span-2"
              />
              {data.reviewed_at && (
                <DetailField
                  label="Reviewed"
                  value={formatDateTime(data.reviewed_at)}
                  icon={<CheckCircle2 className="h-3.5 w-3.5" />}
                  className="sm:col-span-2"
                />
              )}
            </DetailSection>

            {data.rejection_reason && (
              <section className="rounded-xl border border-red-200 bg-red-50/60 p-5">
                <h2 className="text-sm font-semibold text-red-800">
                  Rejection Reason
                </h2>
                <p className="mt-2 whitespace-pre-line text-sm leading-relaxed text-red-700">
                  {data.rejection_reason}
                </p>
              </section>
            )}

            {isPending && (
              <section className="rounded-xl border bg-muted/30 p-5">
                <h2 className="text-sm font-semibold">Review checklist</h2>
                <ul className="mt-3 space-y-2 text-sm text-muted-foreground">
                  <li>• Verify business name, type, and address look legitimate</li>
                  <li>• Preview or download all uploaded documents</li>
                  <li>• Confirm owner contact details are reachable</li>
                  <li>• Approve to create business code and owner login</li>
                </ul>
              </section>
            )}
          </div>
        </div>
      </div>

      <Dialog
        open={emailDialog !== null}
        onOpenChange={(open) => {
          if (!open && !sendEmail.isPending) {
            closeEmailDialog();
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Business Registration Approved</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            The registration for {emailDialog?.businessName} has been approved
            successfully.
          </p>
          <p className="text-sm text-muted-foreground">
            Would you like to send the Business Code and first-login
            instructions to {emailDialog?.ownerEmail} now?
          </p>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              disabled={sendEmail.isPending}
              onClick={closeEmailDialog}
            >
              Not Now
            </Button>
            <Button
              type="button"
              disabled={sendEmail.isPending}
              onClick={() => sendEmail.mutate()}
            >
              {sendEmail.isPending ? "Sending…" : "Send Email"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={rejectOpen}
        onOpenChange={(open) => {
          if (reject.isPending) return;
          setRejectOpen(open);
          if (!open) {
            setSelectedReasons([]);
            setOtherExplanation("");
          }
        }}
      >
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Reject Registration</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Select one or more reasons. These will be included in the rejection
            email sent to the business owner.
          </p>
          <div className="space-y-2">
            {REGISTRATION_REJECTION_REASONS.map((option) => {
              const checked = selectedReasons.includes(option.id);
              return (
                <label
                  key={option.id}
                  className={`flex cursor-pointer items-start gap-3 rounded-lg border px-3 py-2.5 text-sm ${
                    checked
                      ? "border-[#1E3A5F] bg-[#EAF2FB]"
                      : "border-slate-200 bg-white"
                  }`}
                >
                  <input
                    type="checkbox"
                    className="mt-0.5 h-4 w-4 accent-[#1E3A5F]"
                    checked={checked}
                    disabled={reject.isPending}
                    onChange={() =>
                      setSelectedReasons((current) =>
                        toggleRejectionReason(current, option.id)
                      )
                    }
                  />
                  <span className="leading-5 text-[#1F2937]">{option.label}</span>
                </label>
              );
            })}
          </div>
          {selectedReasons.includes(OTHER_REJECTION_REASON_ID) && (
            <Input
              placeholder="Briefly explain the other reason"
              value={otherExplanation}
              disabled={reject.isPending}
              onChange={(e) => setOtherExplanation(e.target.value)}
            />
          )}
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              disabled={reject.isPending}
              onClick={() => setRejectOpen(false)}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              disabled={
                !canConfirmRejection(selectedReasons, otherExplanation) ||
                reject.isPending
              }
              onClick={() => {
                if (
                  reject.isPending ||
                  !canConfirmRejection(selectedReasons, otherExplanation)
                ) {
                  return;
                }
                reject.mutate();
              }}
            >
              {reject.isPending ? "Rejecting…" : "Confirm Rejection"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
