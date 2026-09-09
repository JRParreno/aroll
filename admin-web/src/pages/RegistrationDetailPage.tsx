import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
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
  AdminPage,
  AdminPageBackLink,
  AdminPageContent,
  AdminPageHeader,
} from "@/components/admin/layout/AdminPageLayout";
import {
  DetailField,
  DetailSection,
  formatDateTime,
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
} from "@/lib/api";
import { formatBusinessType } from "@/lib/registrationDocuments";

export function RegistrationDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();

  const [rejectOpen, setRejectOpen] = useState(false);
  const [reason, setReason] = useState("");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["registration", id],
    queryFn: () => getRegistration(id!),
    enabled: Boolean(id),
  });

  const approve = useMutation({
    mutationFn: () => approveRegistration(id!),
    onSuccess: (res: { business_code: string }) => {
      toast.success(`Approved. Business code: ${res.business_code}`);
      qc.invalidateQueries({ queryKey: ["registrations"] });
      qc.invalidateQueries({ queryKey: ["businesses"] });
      navigate("/admin/registrations");
    },
    onError: () => toast.error("Approval failed"),
  });

  const reject = useMutation({
    mutationFn: () => rejectRegistration(id!, reason.trim()),
    onSuccess: () => {
      toast.success("Registration rejected");
      qc.invalidateQueries({ queryKey: ["registrations"] });
      qc.invalidateQueries({ queryKey: ["registration", id] });
      setRejectOpen(false);
      setReason("");
    },
    onError: () => toast.error("Rejection failed"),
  });

  if (isLoading) {
    return (
      <AdminPage>
        <AdminPageHeader
          title="Registration request"
          description="Loading registration details."
        />
        <AdminPageContent>
          <div className="animate-pulse space-y-4">
            <div className="h-4 w-32 rounded bg-muted" />
            <div className="h-8 w-64 rounded bg-muted" />
            <div className="h-40 rounded-2xl bg-muted" />
          </div>
        </AdminPageContent>
      </AdminPage>
    );
  }

  if (isError || !data) {
    return (
      <AdminPage>
        <AdminPageHeader
          title="Registration not found"
          description="This request may have been removed or the link is invalid."
        />
        <AdminPageContent>
          <AdminPageBackLink
            to="/admin/registrations"
            label="Back to pending requests"
          />
        </AdminPageContent>
      </AdminPage>
    );
  }

  const isPending = data.status === "pending";

  return (
    <AdminPage>
      <AdminPageHeader
        title={data.business_name}
        description="Review the submitted business details before approving or rejecting this registration."
        actions={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={data.status} />
            {isPending ? (
              <>
                <Button
                  className="h-10 rounded-xl bg-[#1E3A5F] hover:bg-[#284B73]"
                  onClick={() => approve.mutate()}
                  disabled={approve.isPending || reject.isPending}
                >
                  <CheckCircle2 className="mr-2 h-4 w-4" />
                  Approve
                </Button>
                <Button
                  variant="destructive"
                  className="h-10 rounded-xl"
                  onClick={() => setRejectOpen(true)}
                  disabled={approve.isPending || reject.isPending}
                >
                  <XCircle className="mr-2 h-4 w-4" />
                  Reject
                </Button>
              </>
            ) : null}
          </span>
        }
      />

      <AdminPageContent>
        <AdminPageBackLink
          to="/admin/registrations"
          label="Pending requests"
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
              <section className="rounded-2xl border border-red-200 bg-red-50/60 p-5">
                <h2 className="text-sm font-medium text-red-800">
                  Rejection Reason
                </h2>
                <p className="mt-2 text-sm leading-relaxed text-red-700">
                  {data.rejection_reason}
                </p>
              </section>
            )}

            {isPending && (
              <section className="owner-card-muted p-5">
                <h2 className="text-sm font-medium text-[#1F2937]">Review checklist</h2>
                <ul className="owner-section-subtitle mt-3 space-y-2 text-sm">
                  <li>• Verify business name, type, and address look legitimate</li>
                  <li>• Preview or download all uploaded documents</li>
                  <li>• Confirm owner contact details are reachable</li>
                  <li>• Approve to create business code and owner login</li>
                </ul>
              </section>
            )}
          </div>
        </div>
      </AdminPageContent>

      <Dialog open={rejectOpen} onOpenChange={setRejectOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject Registration</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Provide a clear reason so the business owner understands why this
            request was declined.
          </p>
          <Input
            placeholder="Enter rejection reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setRejectOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              disabled={!reason.trim() || reject.isPending}
              onClick={() => reject.mutate()}
            >
              Confirm Reject
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AdminPage>
  );
}
