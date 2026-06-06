import { cn } from "@/lib/utils";

type ShimmerProps = {
  className?: string;
  variant?: "default" | "light";
  style?: React.CSSProperties;
};

export function Shimmer({ className, variant = "default", style }: ShimmerProps) {
  return (
    <div
      className={cn(
        "rounded-md",
        variant === "light" ? "shimmer-light" : "shimmer",
        className
      )}
      style={style}
      aria-hidden
    />
  );
}

export function ShimmerStatCard({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "rounded-2xl px-6 py-5 shadow-md",
        className
      )}
    >
      <Shimmer variant="light" className="h-4 w-24" />
      <Shimmer variant="light" className="mt-4 h-10 w-16" />
    </div>
  );
}

export function ShimmerChart() {
  return (
    <div className="mt-6 flex h-64 items-end justify-between gap-2 px-2">
      {Array.from({ length: 12 }).map((_, i) => (
        <Shimmer
          key={i}
          className="w-full rounded-t-lg"
          style={{ height: `${35 + (i % 4) * 12}%` }}
        />
      ))}
    </div>
  );
}

export function ShimmerAttendance() {
  return (
    <div className="mt-4 flex flex-col items-center gap-6 sm:flex-row sm:items-center">
      <Shimmer className="h-44 w-44 shrink-0 rounded-full" />
      <div className="w-full space-y-4 sm:flex-1">
        <Shimmer className="h-10 w-full" />
        <Shimmer className="h-10 w-full" />
        <Shimmer className="h-10 w-full" />
      </div>
    </div>
  );
}

export function ShimmerActivityList() {
  return (
    <div className="mt-4 space-y-3">
      {Array.from({ length: 4 }).map((_, i) => (
        <Shimmer key={i} className="h-14 w-full rounded-xl" />
      ))}
    </div>
  );
}
