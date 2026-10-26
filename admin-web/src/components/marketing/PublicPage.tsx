import { useState } from "react";
import { Link } from "react-router-dom";
import { AboutArollDialog } from "@/components/marketing/AboutArollDialog";
import { cn } from "@/lib/utils";

const LOGO_SRC = "/branding/logo.png";

/** Visible artwork inside logo.png is 250×168, inset from a 400×261 canvas. */
export function PublicLogoMark({ className }: { className?: string }) {
  return (
    <span className={cn("relative block overflow-hidden", className)}>
      <img
        src={LOGO_SRC}
        alt=""
        className="pointer-events-none absolute max-w-none select-none"
        style={{
          width: "160%",
          height: "155.357%",
          left: "-33.2%",
          top: "-39.286%",
        }}
      />
    </span>
  );
}

export const publicFieldClass =
  "h-11 rounded-xl border border-[#DBEAFE] bg-[#F8FBFF] text-[#172554] shadow-none placeholder:text-[#94A3B8] focus-visible:ring-[#2563EB]";

export const publicPrimaryButtonClass =
  "h-11 rounded-xl bg-[#2563EB] text-white shadow-none hover:bg-[#1D4ED8] focus-visible:ring-[#2563EB]";

export function PublicPage({
  children,
  showLoginLink = false,
  showHeaderLogo = true,
}: {
  children: React.ReactNode;
  showLoginLink?: boolean;
  showHeaderLogo?: boolean;
}) {
  const [aboutOpen, setAboutOpen] = useState(false);

  return (
    <div
      className="flex min-h-screen flex-col text-white"
      style={{
        backgroundColor: "#071426",
        backgroundImage:
          "radial-gradient(900px 420px at 12% -8%, rgba(37,99,235,0.28), transparent 58%), linear-gradient(rgba(148,163,184,0.07) 1px, transparent 1px), linear-gradient(90deg, rgba(148,163,184,0.07) 1px, transparent 1px)",
        backgroundSize: "auto, 64px 64px, 64px 64px",
      }}
    >
      <header
        className={`mx-auto flex w-full max-w-6xl items-center gap-4 px-5 py-2 sm:px-8 ${
          showHeaderLogo ? "justify-between" : "justify-end"
        }`}
      >
        {showHeaderLogo ? (
          <Link to="/owner-login" className="inline-flex shrink-0" aria-label="Aroll+ owner login">
            <PublicLogoMark className="h-[73px] w-[108px] sm:h-[88px] sm:w-[132px] lg:h-[101px] lg:w-[150px]" />
          </Link>
        ) : null}
        <nav
          className={`flex items-center gap-5 text-sm font-medium text-white/85 ${
            showHeaderLogo ? "" : "translate-y-5"
          }`}
        >
          <button
            type="button"
            className="underline-offset-4 hover:text-white hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#60A5FA] focus-visible:ring-offset-2 focus-visible:ring-offset-[#071426]"
            onClick={() => setAboutOpen(true)}
          >
            About Aroll+
          </button>
          {showLoginLink ? (
            <Link
              to="/owner-login"
              className="underline-offset-4 hover:text-white hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#60A5FA] focus-visible:ring-offset-2 focus-visible:ring-offset-[#071426]"
            >
              Login
            </Link>
          ) : null}
        </nav>
      </header>
      <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col items-stretch px-5 pb-5 pt-1 sm:px-8">
        {children}
      </main>
      <AboutArollDialog open={aboutOpen} onOpenChange={setAboutOpen} />
    </div>
  );
}
