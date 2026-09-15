import { Link, useLocation } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { OwnerNotificationBell } from "@/components/owner/OwnerNotificationBell";
import { cn } from "@/lib/utils";

export const ownerPageContentClassName =
  "mx-auto w-full max-w-6xl space-y-6 px-5 py-6 sm:px-8 sm:py-8";

type OwnerPageBackLinkProps = {
  to: string;
  label?: string;
  className?: string;
};

export function OwnerPageBackLink({
  to,
  label = "Back",
  className,
}: OwnerPageBackLinkProps) {
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

type OwnerPageProps = {
  children: React.ReactNode;
  className?: string;
};

export function OwnerPage({ children, className }: OwnerPageProps) {
  return <div className={cn("flex min-h-full min-w-0 flex-col", className)}>{children}</div>;
}

type OwnerPageHeaderProps = {
  title: React.ReactNode;
  description?: React.ReactNode;
  eyebrow?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
};

export function OwnerPageHeader({
  title,
  description,
  eyebrow,
  actions,
  className,
}: OwnerPageHeaderProps) {
  const { pathname } = useLocation();
  const onNotifications =
    pathname === "/owner/notifications" ||
    pathname.startsWith("/owner/notifications/");

  return (
    <header className={cn("owner-page-header", className)}>
      <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-[#1E3A5F]/15 to-transparent" />
      <div className="pointer-events-none absolute -right-16 -top-20 h-44 w-44 rounded-full bg-[#1E3A5F]/[0.035]" />
      <div className="pointer-events-none absolute -left-10 bottom-0 h-28 w-28 rounded-full bg-[#284B73]/[0.03]" />
      <div className="owner-page-header-inner">
        <div className="owner-page-header-copy">
          <p className="owner-page-header-eyebrow owner-label uppercase tracking-[0.14em] text-[#6B7280]">
            {eyebrow || "\u00A0"}
          </p>
          <h1 className="owner-page-title">{title}</h1>
          <p className="owner-page-header-description owner-section-subtitle max-w-2xl">
            {description || "\u00A0"}
          </p>
        </div>
        <div className="owner-page-header-tools">
          {actions}
          {onNotifications ? null : <OwnerNotificationBell />}
        </div>
      </div>
    </header>
  );
}

type OwnerPageContentProps = {
  children: React.ReactNode;
  className?: string;
};

export function OwnerPageContent({ children, className }: OwnerPageContentProps) {
  return (
    <div className={cn(ownerPageContentClassName, className)}>{children}</div>
  );
}

type OwnerCardProps = {
  children: React.ReactNode;
  className?: string;
  muted?: boolean;
};

/** Shared white panel used across owner pages (UI only). */
export function OwnerCard({ children, className, muted = false }: OwnerCardProps) {
  return (
    <div
      className={cn(muted ? "owner-card-muted" : "owner-card", className)}
    >
      {children}
    </div>
  );
}
