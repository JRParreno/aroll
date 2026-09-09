import { Link } from "react-router-dom";
import { cn } from "@/lib/utils";

type AuthLegalLinksProps = {
  className?: string;
};

export function AuthLegalLinks({ className }: AuthLegalLinksProps) {
  return (
    <p className={cn("text-center text-xs leading-5 text-[#6B7280]", className)}>
      <Link
        to="/legal/docs/terms"
        className="font-medium text-[#1E3A5F] underline underline-offset-2"
      >
        Terms & Conditions
      </Link>
      <span className="mx-1.5 text-[#9CA3AF]">·</span>
      <Link
        to="/legal/docs/privacy"
        className="font-medium text-[#1E3A5F] underline underline-offset-2"
      >
        Privacy Policy
      </Link>
    </p>
  );
}
