import { Link } from "react-router-dom";
import { cn } from "@/lib/utils";
import { ShimmerStatCard } from "@/components/ui/shimmer";

type StatCardProps = {
  label: string;
  value: number | string;
  subtitle?: string;
  to?: string;
  className?: string;
  loading?: boolean;
};

export function StatCard({ label, value, subtitle, to, className, loading }: StatCardProps) {
  if (loading) {
    return <ShimmerStatCard className={className} />;
  }

  const content = (
    <>
      <p className="text-sm font-medium opacity-90">{label}</p>
      <p className="mt-2 text-4xl font-bold tracking-tight">{value}</p>
      {subtitle && (
        <p className="mt-1 text-xs opacity-75">{subtitle}</p>
      )}
    </>
  );

  const cardClassName = cn(
    "rounded-2xl px-6 py-5 text-white shadow-md",
    to && "block transition-all hover:scale-[1.02] hover:shadow-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50",
    className
  );

  if (to) {
    return (
      <Link to={to} className={cardClassName}>
        {content}
      </Link>
    );
  }

  return <div className={cardClassName}>{content}</div>;
}
