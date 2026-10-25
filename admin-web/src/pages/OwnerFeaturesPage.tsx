import { Link } from "react-router-dom";
import { ownerFeatureCards } from "@/components/marketing/OwnerPublicChrome";

const reasons = [
  {
    title: "Workforce information stays together",
    text: "Employee records, positions, schedules, and workplace setup live in the same owner workspace.",
  },
  {
    title: "Schedules and attendance are easier to review",
    text: "See who is scheduled, then review attendance records and shift history without leaving Aroll+.",
  },
  {
    title: "Supported workflows share one portal",
    text: "Leave requests, payroll periods, payslips, and notifications sit alongside day-to-day team administration.",
  },
  {
    title: "Everyday administration is easier to find",
    text: "Business setup, location, and owner settings stay with the tools you use to run the team.",
  },
] as const;

export function OwnerFeaturesPage() {
  return (
    <div className="min-h-screen bg-[#F4F6F8] text-[#111827]">
      <main>
        <section className="bg-white">
          <div className="mx-auto max-w-6xl px-4 py-12 sm:px-6 lg:px-8">
            <h2 className="text-2xl font-semibold tracking-tight text-[#111827]">
              What is Aroll+?
            </h2>
            <div className="mt-4 max-w-3xl space-y-3 text-sm leading-6 text-[#4B5563] sm:text-[0.95rem]">
              <p>
                Aroll+ is a practical workspace for owners who need their team
                operations in one place. It is built for the daily work of
                running a business: who is employed, which position they hold,
                when they are scheduled, and how attendance and pay are recorded.
              </p>
              <p>
                Employees can record attendance with face recognition. Owners
                review those records, manage leave, and follow payroll from the
                web owner portal. Workplace location, shifts, holidays, and rest
                days are part of business setup, so the rules of the workplace
                stay with the team that uses them.
              </p>
            </div>
          </div>
        </section>

        <section id="capabilities" className="scroll-mt-6">
          <div className="mx-auto max-w-6xl px-4 py-12 sm:px-6 lg:px-8">
            <h2 className="text-2xl font-semibold tracking-tight text-[#111827]">
              Features
            </h2>
            <p className="mt-3 max-w-2xl text-sm leading-6 text-[#6B7280]">
              These are capabilities already available in Aroll+. Each one is
              part of the owner portal or the employee attendance flow.
            </p>
            <ul className="mt-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              {ownerFeatureCards.map((feature) => {
                const Icon = feature.icon;
                return (
                  <li
                    key={feature.title}
                    className="min-w-0 rounded-2xl border border-slate-200/90 bg-white p-4"
                  >
                    <span className="inline-flex h-9 w-9 items-center justify-center rounded-lg bg-[#EAF2FB] text-[#1E3A5F]">
                      <Icon className="h-4 w-4" aria-hidden="true" />
                    </span>
                    <h3 className="mt-3 text-sm font-medium text-[#1F2937]">
                      {feature.title}
                    </h3>
                    <p className="mt-1.5 text-sm leading-6 text-[#6B7280]">
                      {feature.text}
                    </p>
                  </li>
                );
              })}
            </ul>
          </div>
        </section>

        <section className="border-t border-slate-200/80 bg-white">
          <div className="mx-auto max-w-6xl px-4 py-12 sm:px-6 lg:px-8">
            <h2 className="text-2xl font-semibold tracking-tight text-[#111827]">
              Why Aroll+?
            </h2>
            <ul className="mt-6 grid gap-4 md:grid-cols-2">
              {reasons.map((reason) => (
                <li
                  key={reason.title}
                  className="min-w-0 rounded-2xl border border-slate-200/90 bg-[#F8FAFC] p-4"
                >
                  <h3 className="text-sm font-medium text-[#1F2937]">{reason.title}</h3>
                  <p className="mt-1.5 text-sm leading-6 text-[#6B7280]">{reason.text}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-4 py-14 text-center sm:px-6 lg:px-8">
          <h2 className="text-2xl font-semibold tracking-tight text-[#1E3A5F] sm:text-3xl">
            Ready to simplify your team&apos;s daily operations?
          </h2>
          <p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-[#6B7280]">
            Sign in to the owner portal with your business code and owner
            credentials.
          </p>
          <Link
            to="/owner-login"
            className="mt-6 inline-flex h-11 items-center justify-center rounded-xl bg-[#1E3A5F] px-5 text-sm font-medium text-white hover:bg-[#284B73]"
          >
            Owner sign in
          </Link>
        </section>
      </main>
    </div>
  );
}
