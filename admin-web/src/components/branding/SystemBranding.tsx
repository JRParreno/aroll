import { cn } from "@/lib/utils";

const SYSTEM_LOGO_SRC = "/branding/logo.png";

type SystemLogoProps = {
  className?: string;
  alt?: string;
};

export function SystemLogo({
  className,
  alt = "Aroll+ system logo",
}: SystemLogoProps) {
  return (
    <img
      src={SYSTEM_LOGO_SRC}
      alt={alt}
      className={cn("block object-contain", className)}
    />
  );
}

type SystemBrandPanelProps = {
  description?: string;
};

export function SystemBrandPanel({
  description = "Face Recognition Attendance and Payroll",
}: SystemBrandPanelProps) {
  return (
    <aside className="hidden min-h-screen items-center justify-center bg-[#1E3A5F] px-10 text-white lg:flex">
      <div className="flex max-w-sm flex-col items-center text-center">
        <SystemLogo className="h-auto w-full max-w-[320px]" />
        <p className="mt-4 max-w-64 text-sm leading-snug text-white/65">
          {description}
        </p>
      </div>
    </aside>
  );
}
