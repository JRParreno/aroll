import { useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  BadgeDollarSign,
  ClipboardList,
  LifeBuoy,
  Lightbulb,
  LockKeyhole,
  Mail,
  ShieldAlert,
  TriangleAlert,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { getMe, sendOwnerSupportEmail } from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { PrototypeNotice } from "@/components/tenant/PrototypeNotice";
import {
  SUPPORT_EMAIL,
  SUPPORT_MESSAGE_MAX,
  claimSupportSubmit,
  supportRequestErrorMessage,
  validateSupportDraft,
} from "@/lib/supportEmail";
import { cn } from "@/lib/utils";

const concernTopics = [
  {
    title: "System Errors & Technical Problems",
    description:
      "For errors, unexpected behavior, pages not loading correctly, or features that are not working as expected.",
    icon: TriangleAlert,
  },
  {
    title: "Account & Access",
    description:
      "For login problems, account activation, password concerns, or access-related issues.",
    icon: LockKeyhole,
  },
  {
    title: "Attendance & Employee Management",
    description:
      "For concerns related to employee attendance, Time In/Time Out, schedules, or employee management.",
    icon: ClipboardList,
  },
  {
    title: "Payroll",
    description:
      "For questions or problems related to payroll settings, salary computation, payroll records, or payslips.",
    icon: BadgeDollarSign,
  },
  {
    title: "Suggestions & Feedback",
    description:
      "For suggestions, feature requests, or ideas that could improve Aroll+.",
    icon: Lightbulb,
  },
] as const;

const reportDetails = [
  "Business name",
  "Brief description of the problem",
  "What you were trying to do",
  "What happened",
  "Screenshot of the error, if applicable",
  "Approximate date and time of the issue",
];

export function OwnerHelpPage() {
  const [subject, setSubject] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [noticeIsError, setNoticeIsError] = useState(false);
  const sendingRef = useRef(false);
  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const businessName = me?.business_name?.trim() || "Your signed-in business";

  async function sendSupportEmail() {
    const validation = validateSupportDraft(subject, message);
    if (validation) {
      setNoticeIsError(true);
      setNotice(validation);
      return;
    }
    if (!claimSupportSubmit(sendingRef)) return;
    setSending(true);
    setNotice(null);
    try {
      const result = await sendOwnerSupportEmail({
        subject: subject.trim(),
        message: message.trim(),
      });
      setSubject("");
      setMessage("");
      setNoticeIsError(false);
      setNotice(result.detail);
      toast.success("Support message accepted", { description: result.detail });
    } catch (error) {
      const detail = supportRequestErrorMessage(error);
      setNoticeIsError(true);
      setNotice(detail);
      toast.error("Support message was not sent", { description: detail });
    } finally {
      sendingRef.current = false;
      setSending(false);
    }
  }

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Help & Support"
        description="Need assistance with Aroll+? We're here to help."
      />

      <OwnerPageContent>
        <PrototypeNotice />
        <OwnerCard className="p-5 sm:p-6">
          <p className="max-w-3xl text-sm leading-relaxed text-[#6B7280]">
            Find helpful information about using your Aroll+ workspace. If you
            encounter an error, experience a problem while using the system, or
            have suggestions for improvement, our support team is available to
            assist you.
          </p>
        </OwnerCard>

        <section>
          <h2 className="owner-section-kicker">
            Common Concerns
          </h2>
          <div className="grid gap-4 md:grid-cols-2">
            {concernTopics.map((topic, index) => {
              const Icon = topic.icon;
              return (
                <OwnerCard
                  className={cn(
                    "h-full p-5 transition hover:border-[#C5D4E3] hover:shadow-[0_8px_24px_rgba(15,23,42,0.06)]",
                    index === concernTopics.length - 1 && "md:col-span-2"
                  )}
                  key={topic.title}
                >
                  <div className="flex items-start gap-4">
                    <span className="owner-icon-well h-10 w-10 shrink-0">
                      <Icon className="h-5 w-5" />
                    </span>
                    <div className="min-w-0">
                      <h3 className="text-sm font-semibold text-[#1F2937]">
                        {topic.title}
                      </h3>
                      <p className="mt-1 text-sm leading-relaxed text-[#6B7280]">
                        {topic.description}
                      </p>
                    </div>
                  </div>
                </OwnerCard>
              );
            })}
          </div>
        </section>

        <OwnerCard className="p-5 sm:p-6">
          <div className="flex items-start gap-4">
            <span className="owner-icon-well h-12 w-12 shrink-0">
              <LifeBuoy className="h-5 w-5" />
            </span>
            <div className="min-w-0">
              <h2 className="text-base font-semibold text-[#1F2937]">
                Contact Aroll+ Support
              </h2>
              <p className="mt-1 max-w-2xl text-sm leading-relaxed text-[#6B7280]">
                If you encounter a problem that you cannot resolve or would
                like to send feedback, you can contact the Aroll+ support team
                through email.
              </p>
            </div>
          </div>
          <form
            className="mt-5 grid gap-4"
            onSubmit={(event) => {
              event.preventDefault();
              void sendSupportEmail();
            }}
          >
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <p className="text-sm font-medium text-[#374151]">Recipient</p>
                <p className="mt-1 text-sm font-semibold text-[var(--owner-navy)]">
                  {SUPPORT_EMAIL}
                </p>
              </div>
              <div>
                <p className="text-sm font-medium text-[#374151]">Business name</p>
                <p className="mt-1 text-sm text-[#1F2937]">{businessName}</p>
              </div>
            </div>
            <label className="grid gap-1.5 text-sm font-medium text-[#374151]">
              Subject
              <input
                className="h-10 rounded-xl border border-slate-200 bg-white px-3 text-sm font-normal text-[#1F2937] outline-none focus:border-[var(--owner-navy)]"
                disabled={sending}
                maxLength={120}
                onChange={(event) => setSubject(event.target.value)}
                required
                value={subject}
              />
            </label>
            <label className="grid gap-1.5 text-sm font-medium text-[#374151]">
              Concern or message
              <textarea
                className="min-h-32 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-normal text-[#1F2937] outline-none focus:border-[var(--owner-navy)]"
                disabled={sending}
                maxLength={SUPPORT_MESSAGE_MAX}
                onChange={(event) => setMessage(event.target.value)}
                required
                value={message}
              />
            </label>
            <div>
              <Button
                className="h-10 rounded-xl bg-[var(--owner-button)] px-4 hover:bg-[var(--owner-navy-soft)]"
                disabled={sending}
                type="submit"
              >
                <Mail className="mr-2 h-4 w-4" />
                {sending ? "Sending…" : "Send Email"}
              </Button>
            </div>
          </form>
          {notice ? (
            <p
              className={cn(
                "mt-4 rounded-xl border px-4 py-3 text-sm leading-relaxed",
                noticeIsError
                  ? "border-red-200 bg-red-50 text-red-800"
                  : "border-slate-200 bg-[#FAFBFC] text-[#374151]",
              )}
              role="status"
            >
              {notice}
            </p>
          ) : null}
        </OwnerCard>

        <OwnerCard className="p-5 sm:p-6">
          <div className="flex items-start gap-4">
            <span className="owner-icon-well h-10 w-10 shrink-0">
              <ShieldAlert className="h-5 w-5" />
            </span>
            <div className="min-w-0">
              <h2 className="text-base font-semibold text-[#1F2937]">
                When Reporting a Problem
              </h2>
              <p className="mt-1 text-sm leading-relaxed text-[#6B7280]">
                Including the following details helps our support team review
                your concern more quickly.
              </p>
              <ul className="mt-4 space-y-2 text-sm text-[#374151]">
                {reportDetails.map((item) => (
                  <li className="flex gap-2" key={item}>
                    <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--owner-button)]" />
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
              <p className="mt-4 rounded-xl border border-slate-200 bg-[#FAFBFC] px-4 py-3 text-xs leading-relaxed text-[#6B7280]">
                Please do not include passwords, authentication codes, or other
                sensitive credentials in your support email.
              </p>
            </div>
          </div>
        </OwnerCard>
      </OwnerPageContent>
    </OwnerPage>
  );
}
