import {
  BadgeDollarSign,
  Bell,
  CalendarDays,
  ClipboardCheck,
  MapPin,
  Palmtree,
  Users,
  WalletCards,
} from "lucide-react";

export const ownerFeatureCards = [
  {
    title: "Employee management",
    text: "Keep employee records in the owner workspace and manage who belongs to the business.",
    icon: Users,
  },
  {
    title: "Positions and pay rates",
    text: "Set job positions with the daily and hourly rates used by your workplace.",
    icon: WalletCards,
  },
  {
    title: "Schedules and shifts",
    text: "Build schedules around the shifts, holidays, and rest days you configure.",
    icon: CalendarDays,
  },
  {
    title: "Attendance monitoring",
    text: "Review attendance and shift history. Employees can record time in and time out with face recognition.",
    icon: ClipboardCheck,
  },
  {
    title: "Workplace location",
    text: "Save the workplace address and the attendance radius used for location checks.",
    icon: MapPin,
  },
  {
    title: "Payroll",
    text: "Follow payroll periods, review payroll records, and open employee payslips.",
    icon: BadgeDollarSign,
  },
  {
    title: "Leave",
    text: "Review leave requests and keep the workplace leave policy with the rest of your setup.",
    icon: Palmtree,
  },
  {
    title: "Notifications",
    text: "See owner notifications for leave and scheduling updates in one list.",
    icon: Bell,
  },
] as const;
