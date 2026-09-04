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
import { Button } from "@/components/ui/button";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { PrototypeNotice } from "@/components/tenant/PrototypeNotice";
import { cn } from "@/lib/utils";

const SUPPORT_EMAIL = "arollplus1111@gmail.com";
const SUPPORT_MAILTO = `mailto:${SUPPORT_EMAIL}`;

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
          <h2 className="mb-4 text-sm font-medium uppercase tracking-wide text-[#6B7280]">
            Common Concerns
          </h2>
          <div className="grid gap-4 md:grid-cols-2">
            {concernTopics.map((topic, index) => {
              const Icon = topic.icon;
              return (
                <OwnerCard
                  className={cn(
                    "h-full p-5",
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
          <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex min-w-0 items-start gap-4">
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
                <p className="mt-3 text-sm text-[#374151]">
                  <span className="font-medium text-[#6B7280]">Email:</span>{" "}
                  <a
                    className="font-semibold text-[#1E3A5F] hover:underline"
                    href={SUPPORT_MAILTO}
                  >
                    {SUPPORT_EMAIL}
                  </a>
                </p>
              </div>
            </div>
            <Button
              asChild
              className="h-10 shrink-0 rounded-xl bg-[#1E3A5F] px-4 hover:bg-[#284B73]"
            >
              <a href={SUPPORT_MAILTO}>
                <Mail className="mr-2 h-4 w-4" />
                Send Email
              </a>
            </Button>
          </div>
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
                    <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-[#1E3A5F]" />
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
