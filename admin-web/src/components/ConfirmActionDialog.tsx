import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

export type ConfirmActionTone = "primary" | "danger";

type ConfirmActionDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  icon: ReactNode;
  title: string;
  description: ReactNode;
  confirmLabel: string;
  onConfirm: () => void;
  cancelLabel?: string;
  tone?: ConfirmActionTone;
  confirmDisabled?: boolean;
  cancelDisabled?: boolean;
};

const toneStyles: Record<
  ConfirmActionTone,
  { well: string; confirm: string }
> = {
  primary: {
    well: "bg-[var(--owner-well)] text-[var(--owner-navy)]",
    confirm: "bg-[var(--owner-button)] text-white hover:bg-[var(--owner-navy-soft)]",
  },
  danger: {
    well: "bg-rose-50 text-rose-700",
    // Softer than default destructive red-600
    confirm: "bg-[#B91C1C] text-white hover:bg-[#991B1B]",
  },
};

/** Shared Aroll+ confirmation dialog shell (visual only). */
export function ConfirmActionDialog({
  open,
  onOpenChange,
  icon,
  title,
  description,
  confirmLabel,
  onConfirm,
  cancelLabel = "Cancel",
  tone = "primary",
  confirmDisabled = false,
  cancelDisabled = false,
}: ConfirmActionDialogProps) {
  const styles = toneStyles[tone];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md gap-0 overflow-hidden border-slate-200 p-0 sm:rounded-2xl">
        <div className="px-6 pb-2 pt-7 text-center">
          <div
            className={cn(
              "mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl",
              styles.well
            )}
          >
            {icon}
          </div>
          <DialogHeader className="space-y-2 text-center sm:text-center">
            <DialogTitle className="text-lg font-extrabold tracking-tight text-[#111827]">
              {title}
            </DialogTitle>
            <DialogDescription asChild>
              <div className="max-h-[50vh] overflow-y-auto text-sm leading-relaxed text-[#6B7280]">
                {description}
              </div>
            </DialogDescription>
          </DialogHeader>
        </div>
        <DialogFooter className="flex-row gap-2.5 border-t border-[#E8EEF4] px-6 py-4 sm:justify-stretch sm:space-x-0">
          <Button
            type="button"
            variant="outline"
            className="h-11 flex-1 rounded-xl"
            disabled={cancelDisabled}
            onClick={() => onOpenChange(false)}
          >
            {cancelLabel}
          </Button>
          <Button
            type="button"
            className={cn("h-11 flex-1 rounded-xl", styles.confirm)}
            disabled={confirmDisabled}
            onClick={onConfirm}
          >
            {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
