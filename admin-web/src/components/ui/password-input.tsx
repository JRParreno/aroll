import { Eye, EyeOff } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

type PasswordInputProps = {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  required?: boolean;
  minLength?: number;
  className?: string;
  inputClassName?: string;
  hint?: string;
};

export function PasswordInput({
  id,
  label,
  value,
  onChange,
  placeholder,
  required,
  minLength,
  className,
  inputClassName,
  hint,
}: PasswordInputProps) {
  const [visible, setVisible] = useState(false);

  return (
    <div className={cn("space-y-2", className)}>
      <Label htmlFor={id}>{label}</Label>
      <div className="relative">
        <Input
          id={id}
          type={visible ? "text" : "password"}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
          required={required}
          minLength={minLength}
          className={cn("pr-10", inputClassName)}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-0 top-0 h-10 w-10 text-muted-foreground hover:text-foreground"
          onClick={() => setVisible((current) => !current)}
          aria-label={visible ? "Hide password" : "Show password"}
        >
          {visible ? (
            <EyeOff className="h-4 w-4" />
          ) : (
            <Eye className="h-4 w-4" />
          )}
        </Button>
      </div>
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

type PasswordRequirementsProps = {
  password: string;
  confirmPassword?: string;
};

export function PasswordRequirements({
  password,
  confirmPassword,
}: PasswordRequirementsProps) {
  const checks = [
    { label: "At least 8 characters", ok: password.length >= 8 },
    { label: "At least one uppercase letter", ok: /[A-Z]/.test(password) },
    {
      label: "At least one special character",
      ok: /[!@#$%^&*(),.?":{}|<>_\-+=[\]\\;/'`~]/.test(password),
    },
  ];

  if (confirmPassword !== undefined) {
    checks.push({
      label: "Passwords match",
      ok: password.length > 0 && password === confirmPassword,
    });
  }

  return (
    <ul className="space-y-1 text-xs">
      {checks.map((check) => (
        <li
          key={check.label}
          className={check.ok ? "text-emerald-700" : "text-muted-foreground"}
        >
          {check.ok ? "✓" : "•"} {check.label}
        </li>
      ))}
    </ul>
  );
}
