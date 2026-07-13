import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { cn } from "@/lib/utils";

export const ownerPageContentClassName =
  "mx-auto w-full max-w-6xl space-y-6 px-5 py-6 sm:px-8";

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
        "inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-foreground",
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
  return <div className={cn("min-h-full", className)}>{children}</div>;
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
  return (
    <header
      className={cn(
        "border-b border-slate-200 bg-white px-5 py-6 sm:px-8",
        className
      )}
    >
      <div
        className={cn(
          "mx-auto flex max-w-6xl flex-col gap-4",
          actions && "lg:flex-row lg:items-center lg:justify-between"
        )}
      >
        <div>
          {eyebrow ? (
            <p className="text-sm font-medium text-[#6B7280]">{eyebrow}</p>
          ) : null}
          <h1
            className={cn(
              "text-2xl font-semibold text-[#1F2937]",
              eyebrow && "mt-1"
            )}
          >
            {title}
          </h1>
          {description ? (
            <p className="mt-1 text-sm text-[#6B7280]">{description}</p>
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

type OwnerPageContentProps = {
  children: React.ReactNode;
  className?: string;
};

export function OwnerPageContent({ children, className }: OwnerPageContentProps) {
  return (
    <div className={cn(ownerPageContentClassName, className)}>{children}</div>
  );
}
