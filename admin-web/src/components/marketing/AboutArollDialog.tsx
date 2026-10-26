import { useMemo, useRef } from "react";
import {
  BadgeDollarSign,
  CalendarDays,
  ScanFace,
  Smartphone,
  X,
} from "lucide-react";
import { ownerFeatureCards } from "@/components/marketing/OwnerPublicChrome";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  ABOUT_DOWNLOAD_TEXT,
  ANDROID_APK_URL,
  aboutDialogOpenAfter,
  groupFeatureCards,
} from "@/lib/aboutAroll";
import { apkQrSvg } from "@/lib/apkQr";

const highlights = [
  { icon: ScanFace, label: "Facial Recognition Attendance" },
  { icon: CalendarDays, label: "Shift and Schedule Management" },
  { icon: BadgeDollarSign, label: "Payroll History and Payslips" },
] as const;

function scrollWithin(root: HTMLElement | null, id: string) {
  const target = root?.querySelector<HTMLElement>(`#${id}`);
  if (!root || !target) return;
  const top = target.getBoundingClientRect().top - root.getBoundingClientRect().top + root.scrollTop - 8;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  root.scrollTo({ top, behavior: reduce ? "auto" : "smooth" });
}

function AttendancePreview() {
  return (
    <article className="rounded-2xl border border-[#DBEAFE] bg-white p-4 shadow-[0_20px_50px_rgba(37,99,235,0.12)]">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm font-semibold text-[#172554]">Attendance</p>
        <span className="rounded-full bg-[#EFF6FF] px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-[#1D4ED8]">
          Preview
        </span>
      </div>
      <div className="mt-4 space-y-2.5">
        {["Time in", "Time out"].map((label) => (
          <div key={label} className="flex items-center gap-3 rounded-xl bg-[#F8FBFF] px-3 py-2.5">
            <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#DBEAFE] text-[#1D4ED8]">
              <ScanFace className="h-4 w-4" aria-hidden="true" />
            </span>
            <span>
              <span className="block text-xs text-[#475569]">{label}</span>
              <span className="block text-sm font-medium text-[#172554]">Face recognition</span>
            </span>
          </div>
        ))}
      </div>
    </article>
  );
}

function SchedulePreview() {
  return (
    <article className="rounded-2xl border border-[#DBEAFE] bg-white/95 p-4 shadow-[0_16px_40px_rgba(29,78,216,0.1)]">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm font-semibold text-[#172554]">Schedule</p>
        <span className="rounded-full bg-[#EFF6FF] px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-[#1D4ED8]">
          Preview
        </span>
      </div>
      <ul className="mt-3 space-y-2 text-sm text-[#172554]">
        {["Shift", "Rest day", "Holiday"].map((item) => (
          <li key={item} className="flex items-center gap-2 rounded-lg bg-[#F8FBFF] px-3 py-2">
            <CalendarDays className="h-4 w-4 text-[#2563EB]" aria-hidden="true" />
            {item}
          </li>
        ))}
      </ul>
    </article>
  );
}

function PayslipPreview() {
  return (
    <article className="rounded-2xl border border-[#BFDBFE] bg-[#EFF6FF] p-4 shadow-[0_16px_40px_rgba(37,99,235,0.14)]">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm font-semibold text-[#172554]">Payslip</p>
        <span className="rounded-full bg-white px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-[#1D4ED8]">
          Preview
        </span>
      </div>
      <ul className="mt-3 space-y-2 text-sm text-[#172554]">
        {["Pay period", "Payroll history", "Earnings and deductions"].map((item) => (
          <li key={item} className="rounded-lg bg-white/80 px-3 py-2">
            {item}
          </li>
        ))}
      </ul>
    </article>
  );
}

export function AboutArollDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const groups = groupFeatureCards(ownerFeatureCards);
  const qr = useMemo(() => apkQrSvg(ANDROID_APK_URL), []);

  function dismiss(event: "close-button" | "escape" | "outside-click") {
    onOpenChange(aboutDialogOpenAfter(event));
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => onOpenChange(aboutDialogOpenAfter(next ? "open" : "close-button"))}
    >
      <DialogContent
        hideClose
        aria-describedby="about-aroll-description"
        overlayClassName="bg-[#172554]/35 backdrop-blur-[2px]"
        onEscapeKeyDown={() => dismiss("escape")}
        onInteractOutside={() => dismiss("outside-click")}
        className="left-0 top-0 flex h-[100dvh] max-h-[100dvh] w-full max-w-none translate-x-0 translate-y-0 flex-col gap-0 overflow-hidden rounded-none border-0 bg-[#F8FBFF] p-0 shadow-2xl sm:left-1/2 sm:top-1/2 sm:h-[min(920px,calc(100dvh-1.5rem))] sm:max-h-[min(920px,calc(100dvh-1.5rem))] sm:w-[min(1120px,calc(100%-1.5rem))] sm:translate-x-[-50%] sm:translate-y-[-50%] sm:rounded-3xl sm:border sm:border-[#DBEAFE]"
      >
        <header className="flex shrink-0 items-center justify-between gap-3 border-b border-[#DBEAFE] bg-white/95 px-4 py-3 shadow-sm sm:px-6">
          <DialogTitle className="truncate text-lg font-semibold leading-none tracking-tight text-[#172554]">
            Aroll<span className="text-[#2563EB]">+</span>
          </DialogTitle>
          <DialogClose
            aria-label="Close About Aroll+"
            className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[#DBEAFE] bg-white text-[#172554] transition hover:bg-[#EFF6FF] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2563EB]"
            onClick={() => dismiss("close-button")}
          >
            <X className="h-4 w-4" aria-hidden="true" />
          </DialogClose>
        </header>

        <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-8 sm:py-10">
            <section id="about-overview" className="grid items-center gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-12">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#1D4ED8]">
                  Attendance &amp; payroll management
                </p>
                <h2 className="mt-4 max-w-xl text-4xl font-semibold tracking-tight text-[#172554] sm:text-5xl sm:leading-[1.05]">
                  Smarter Attendance.{" "}
                  <span className="bg-gradient-to-r from-[#2563EB] to-[#1D4ED8] bg-clip-text text-transparent">
                    Simpler Payroll.
                  </span>
                </h2>
                <DialogDescription
                  id="about-aroll-description"
                  className="mt-5 max-w-xl text-base leading-7 text-[#475569]"
                >
                  Aroll+ helps small businesses manage attendance, schedules, leave, and payroll.
                </DialogDescription>
                <div className="mt-7">
                  <button
                    type="button"
                    className="inline-flex h-11 items-center justify-center rounded-xl bg-[#2563EB] px-5 text-sm font-semibold text-white shadow-sm transition hover:bg-[#1D4ED8] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2563EB] focus-visible:ring-offset-2"
                    onClick={() => scrollWithin(scrollRef.current, "about-features")}
                  >
                    Explore Features
                  </button>
                </div>
              </div>

              <div>
                <p className="mb-3 text-xs font-medium uppercase tracking-[0.14em] text-[#475569]">
                  Illustrative preview
                </p>
                <div className="relative hidden h-[440px] lg:block">
                  <div
                    aria-hidden="true"
                    className="pointer-events-none absolute left-8 top-10 h-56 w-56 rounded-full bg-[#DBEAFE] blur-3xl"
                  />
                  <div className="absolute right-2 top-0 w-[240px] motion-safe:-rotate-2">
                    <SchedulePreview />
                  </div>
                  <div className="absolute left-0 top-20 z-10 w-[280px] motion-safe:rotate-1">
                    <AttendancePreview />
                  </div>
                  <div className="absolute bottom-2 right-6 z-20 w-[230px] motion-safe:rotate-2">
                    <PayslipPreview />
                  </div>
                </div>
                <div className="grid gap-4 lg:hidden">
                  <AttendancePreview />
                  <SchedulePreview />
                  <PayslipPreview />
                </div>
              </div>
            </section>

            <section aria-label="Product capabilities" className="mt-12 border-y border-[#DBEAFE] py-5">
              <ul className="grid gap-4 sm:grid-cols-3">
                {highlights.map((item) => (
                  <li key={item.label} className="flex items-center gap-3 text-sm font-medium text-[#172554]">
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#EFF6FF] text-[#2563EB]">
                      <item.icon className="h-4 w-4" aria-hidden="true" />
                    </span>
                    {item.label}
                  </li>
                ))}
              </ul>
            </section>

            <section id="about-features" className="mt-14">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#1D4ED8]">Features</p>
              <h2 className="mt-3 max-w-2xl text-3xl font-semibold tracking-tight text-[#172554] sm:text-4xl">
                Everything you need to manage your workforce
              </h2>
              <p className="mt-3 max-w-2xl text-base leading-7 text-[#475569]">
                Attendance, schedules, leave, and payroll, organized the way Aroll+ already works.
              </p>

              {groups.map((group) => (
                <div key={group.id} className="mt-8">
                  <h3 className="text-sm font-semibold uppercase tracking-[0.14em] text-[#475569]">
                    {group.label}
                  </h3>
                  <ul
                    className={
                      group.id === "employee"
                        ? "mt-4 grid"
                        : "mt-4 grid gap-4 md:grid-cols-6"
                    }
                  >
                    {group.features.map((feature, index) => {
                      const Icon = feature.icon;
                      const span =
                        group.id === "owner" ? (index < 2 ? "md:col-span-3" : "md:col-span-2") : "";
                      return (
                        <li
                          key={feature.title}
                          className={`rounded-2xl border border-[#DBEAFE] bg-white p-5 shadow-sm transition duration-200 hover:border-[#BFDBFE] hover:shadow-md motion-safe:hover:-translate-y-0.5 ${span} ${
                            group.id === "employee" ? "sm:flex sm:items-start sm:gap-5" : ""
                          }`}
                        >
                          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-[#EFF6FF] text-[#1D4ED8]">
                            <Icon className="h-5 w-5" aria-hidden="true" />
                          </span>
                          <span className={group.id === "employee" ? "mt-4 block sm:mt-0" : "mt-4 block"}>
                            <span className="block text-base font-semibold text-[#172554]">{feature.title}</span>
                            <span className="mt-1.5 block text-sm leading-6 text-[#475569]">{feature.text}</span>
                          </span>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
            </section>

            <section className="mt-14 overflow-hidden rounded-3xl border border-[#BFDBFE] bg-gradient-to-br from-[#DBEAFE] via-[#EFF6FF] to-white p-6 sm:p-8">
              <div className="grid items-center gap-8 lg:grid-cols-[minmax(0,1fr)_220px]">
                <div>
                  <span className="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-white text-[#2563EB] shadow-sm">
                    <Smartphone className="h-5 w-5" aria-hidden="true" />
                  </span>
                  <h2 className="mt-4 text-3xl font-semibold tracking-tight text-[#172554]">
                    Take Aroll+ with you.
                  </h2>
                  <p className="mt-3 max-w-xl text-base leading-7 text-[#475569]">
                    The Android app lets employees access supported attendance and payroll features from their phones.{" "}
                    {ABOUT_DOWNLOAD_TEXT}
                  </p>
                  <a
                    href={ANDROID_APK_URL}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-6 inline-flex h-11 items-center justify-center rounded-xl bg-[#2563EB] px-5 text-sm font-semibold text-white shadow-sm transition hover:bg-[#1D4ED8] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2563EB] focus-visible:ring-offset-2"
                  >
                    Download Android App
                  </a>
                </div>
                <div className="flex flex-col items-center">
                  <div
                    className="bg-white p-2 shadow-sm [&>svg]:h-[188px] [&>svg]:w-[188px]"
                    role="img"
                    aria-label="QR code for the Aroll+ Android app download"
                    dangerouslySetInnerHTML={{ __html: qr.svg }}
                  />
                  <p className="mt-3 text-center text-sm text-[#475569]">Scan to download the Android app</p>
                </div>
              </div>
            </section>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
