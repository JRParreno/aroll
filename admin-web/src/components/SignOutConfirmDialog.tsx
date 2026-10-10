import { LogOut } from "lucide-react";
import { ConfirmActionDialog } from "@/components/ConfirmActionDialog";

type SignOutConfirmDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: () => void;
};

export function SignOutConfirmDialog({
  open,
  onOpenChange,
  onConfirm,
}: SignOutConfirmDialogProps) {
  return (
    <ConfirmActionDialog
      open={open}
      onOpenChange={onOpenChange}
      icon={<LogOut className="h-5 w-5" strokeWidth={2.25} aria-hidden />}
      title="Sign Out"
      description="Are you sure you want to sign out?"
      confirmLabel="Sign Out"
      tone="primary"
      onConfirm={() => {
        onOpenChange(false);
        onConfirm();
      }}
    />
  );
}
