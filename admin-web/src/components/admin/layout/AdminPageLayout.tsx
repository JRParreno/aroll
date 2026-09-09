import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { cn } from "@/lib/utils";

export const adminPageContentClassName =
  "mx-auto w-full max-w-6xl space-y-6 px-5 py-6 sm:px-8 sm:py-8";

type AdminPageBackLinkProps = {
  to: string;
  label?: string;
  className?: string;
};

export function AdminPageBackLink({
  to,
  label = "Back",
  className,
}: AdminPageBackLinkProps) {
  return (
    <Link
      to={to}
      className={cn(
        "inline-flex items-center gap-2 rounded-lg px-1 py-0.5 text-sm font-medium text-[#6B7280] transition-colors hover:bg-white hover:text-[#1E3A5F]",
        className
      )}
    >
      <ArrowLeft className="h-4 w-4" />
      {label}
    </Link>
  );
}

type AdminPageProps = {
  children: React.ReactNode;
  className?: string;
};

export function AdminPage({ children, className }: AdminPageProps) {
  return (
    <div className={cn("flex min-h-full min-w-0 flex-col", className)}>
      {children}
    </div>
  );
}

type AdminPageHeaderProps = {
  title: React.ReactNode;
  description?: React.ReactNode;
  eyebrow?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
};

export function AdminPageHeader({
  title,
  description,
  eyebrow,
  actions,
  className,
}: AdminPageHeaderProps) {
  return (
    <header
      className={cn(
        "sticky top-0 z-20 shrink-0 overflow-hidden border-b border-slate-200/80 bg-white/90 px-5 py-6 backdrop-blur-sm sm:px-8",
        className
      )}
    >
      <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-[#1E3A5F]/15 to-transparent" />
      <div className="pointer-events-none absolute -right-16 -top-20 h-44 w-44 rounded-full bg-[#1E3A5F]/[0.035]" />
      <div className="pointer-events-none absolute -left-10 bottom-0 h-28 w-28 rounded-full bg-[#284B73]/[0.03]" />
      <div className="relative mx-auto flex max-w-6xl flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          {eyebrow ? (
            <p className="owner-label uppercase tracking-[0.14em] text-[#6B7280]">
              {eyebrow}
            </p>
          ) : null}
          <h1 className={cn("owner-page-title", eyebrow && "mt-1.5")}>
            {title}
          </h1>
          {description ? (
            <p className="owner-section-subtitle mt-1.5 max-w-2xl">
              {description}
            </p>
          ) : null}
        </div>
        {actions ? (
          <div className="flex shrink-0 flex-wrap items-center gap-2">
            {actions}
          </div>
        ) : null}
      </div>
    </header>
  );
}

type AdminPageContentProps = {
  children: React.ReactNode;
  className?: string;
};

export function AdminPageContent({
  children,
  className,
}: AdminPageContentProps) {
  return (
    <div className={cn(adminPageContentClassName, className)}>{children}</div>
  );
}

type AdminCardProps = {
  children: React.ReactNode;
  className?: string;
  muted?: boolean;
};

export function AdminCard({
  children,
  className,
  muted = false,
}: AdminCardProps) {
  return (
    <div className={cn(muted ? "owner-card-muted" : "owner-card", className)}>
      {children}
    </div>
  );
}
