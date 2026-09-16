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
        "flex h-full min-h-[10.25rem] flex-col justify-center rounded-[1.15rem] border px-4 py-4",
        className
      )}
    >
      <Shimmer className="h-3 w-24" />
      <Shimmer className="mt-4 h-8 w-16" />
      <Shimmer className="mt-3 h-3 w-28" />
    </div>
  );
}

export function ShimmerChart() {
  return (
    <div className="mt-4 flex h-44 items-end justify-between gap-2">
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
    <div className="mt-4 grid grid-cols-3 gap-2">
      <Shimmer className="h-16 w-full rounded-xl" />
      <Shimmer className="h-16 w-full rounded-xl" />
      <Shimmer className="h-16 w-full rounded-xl" />
    </div>
  );
}

export function ShimmerActivityList() {
  return (
    <div className="mt-4 space-y-2">
      {Array.from({ length: 5 }).map((_, i) => (
        <Shimmer key={i} className="h-12 w-full rounded-lg" />
      ))}
    </div>
  );
}
