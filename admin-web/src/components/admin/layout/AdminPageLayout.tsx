import { cn } from "@/lib/utils";

export const adminPageContentClassName =
  "mx-auto w-full max-w-6xl space-y-7 px-5 py-6 sm:px-8 sm:py-8";

type AdminPageProps = {
  children: React.ReactNode;
  className?: string;
};

export function AdminPage({ children, className }: AdminPageProps) {
  return (
    <div className={cn("flex min-h-full min-w-0 flex-col bg-[#F4F7FB]", className)}>
      {children}
    </div>
  );
}

type AdminPageHeaderProps = {
  eyebrow?: React.ReactNode;
  title: React.ReactNode;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
};

export function AdminPageHeader({
  eyebrow,
  title,
  description,
  actions,
  className,
}: AdminPageHeaderProps) {
  return (
    <header className={cn("admin-page-header", className)}>
      <div className="admin-page-header-inner">
        <div className="admin-page-header-copy">
          {eyebrow ? (
            <p className="admin-page-header-eyebrow">{eyebrow}</p>
          ) : null}
          <h1 className="admin-page-title">{title}</h1>
          {description ? (
            <p className="admin-page-header-description">{description}</p>
          ) : null}
        </div>
        {actions ? (
          <div className="admin-page-header-tools">{actions}</div>
        ) : null}
      </div>
    </header>
  );
}

type AdminPageContentProps = {
  children: React.ReactNode;
  className?: string;
};

export function AdminPageContent({ children, className }: AdminPageContentProps) {
  return (
    <div className={cn(adminPageContentClassName, className)}>{children}</div>
  );
}
