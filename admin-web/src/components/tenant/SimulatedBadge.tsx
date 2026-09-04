import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

export function SimulatedBadge({
  className,
  label = "Simulated",
}: {
  className?: string;
  label?: string;
}) {
  return (
    <Badge
      variant="secondary"
      className={cn(
        "border-amber-200 bg-amber-50 text-[10px] font-semibold uppercase tracking-wide text-amber-900",
        className
      )}
    >
      {label}
    </Badge>
  );
}

/** Read-only tenant kind from authenticated/admin business flags. */
export function TenantKindBadge({
  isDemo,
  isInternalTest,
}: {
  isDemo?: boolean;
  isInternalTest?: boolean;
}) {
  if (isDemo) {
    return <SimulatedBadge label="DEMO" />;
  }
  if (isInternalTest) {
    return (
      <Badge
        variant="secondary"
        className="border-sky-200 bg-sky-50 text-[10px] font-semibold uppercase tracking-wide text-sky-900"
      >
        INTERNAL TEST
      </Badge>
    );
  }
  return null;
}
