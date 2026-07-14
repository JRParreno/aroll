import { useQuery } from "@tanstack/react-query";
import jsPDF from "jspdf";
import { Download, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  OwnerPage,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import {
  getMe,
  getEmployeePayslip,
  getOwnerPayrollReport,
  type EmployeePayslip,
} from "@/lib/api";
import { ME_QUERY_KEY } from "@/lib/authSession";

function money(value: number) {
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
  }).format(value);
}

export function OwnerPayrollPage() {
  const [search, setSearch] = useState("");
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string | null>(null);
  const [payslipSettings, setPayslipSettings] = useState({
    title: "Payslip",
    employeeSection: "Employee Information",
    earningsSection: "Earnings/Income",
    deductionsSection: "Deductions",
    netPaySection: "NET PAY",
    notes: "(Total Earnings less deductions)",
    headerColor: "#E5E7EB",
    earningsColor: "#FDE68A",
    deductionsColor: "#FECACA",
    netColor: "#BBF7D0",
  });
  const { data: me } = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: getMe,
  });
  const { data, isLoading } = useQuery({
    queryKey: ["owner-payroll-report"],
    queryFn: getOwnerPayrollReport,
  });
  const { data: payslip, isLoading: payslipLoading } = useQuery({
    queryKey: ["employee-payslip", selectedEmployeeId],
    queryFn: () => getEmployeePayslip(selectedEmployeeId!),
    enabled: Boolean(selectedEmployeeId),
  });

  const items = useMemo(() => {
    const needle = search.toLowerCase();
    return (data?.items ?? []).filter((item) =>
      [item.employee_name, item.position_title ?? ""]
        .join(" ")
        .toLowerCase()
        .includes(needle)
    );
  }, [data, search]);
  const businessName =
    me?.business_name ?? localStorage.getItem("aroll_business_name") ?? "Business";
  const businessLogo = me?.branding?.logo_url ?? null;
  const themeButtonColor = me?.branding?.theme.button_color || "#1E3A5F";
  const themeButtonHoverColor = me?.branding?.theme.secondary_color || "#284B73";
  const canEditPayslip = me?.role === "owner" || me?.role === "manager";

  return (
    <OwnerPage>
      <OwnerPageHeader
        title="Payroll"
        //description="Review salary summaries generated from current employee and attendance data."
      />

      <OwnerPageContent>
        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="grid gap-3 lg:grid-cols-[1fr_auto]">
            <div className="relative">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-[#9CA3AF]" />
              <Input className="pl-9" placeholder="Search employee" value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <Button variant="outline" className="gap-2">
              <Download className="h-4 w-4" />
              Download Summary
            </Button>
          </div>
        </section>

        <section className="grid gap-5 xl:grid-cols-2">
          {isLoading ? (
            <p className="text-sm text-[#6B7280]">Loading payroll...</p>
          ) : items.length === 0 ? (
            <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-[#6B7280] shadow-sm">
              No payroll records found.
            </div>
          ) : (
            items.map((item) => (
              <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm" key={item.employee_id}>
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <h2 className="text-base font-semibold text-[#1F2937]">{item.employee_name}</h2>
                    <p className="text-sm text-[#6B7280]">{item.position_title ?? "Employee"}</p>
                    <p className="mt-1 text-xs text-[#9CA3AF]">
                      {item.period_start} to {item.period_end}
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setSelectedEmployeeId(item.employee_id)}
                  >
                    View Payslip
                  </Button>
                </div>
                <div className="mt-5 space-y-3 text-sm">
                  <Row label="Daily Rate" value={money(item.daily_rate)} />
                  <Row label="Worked Days" value={`${item.worked_days} days`} />
                  <Row label="Overtime Pay" value={money(item.overtime_pay)} />
                  <Row label="Deductions" value={money(item.deductions)} />
                  <Row label="Total Salary" value={money(item.total_salary)} strong />
                </div>
              </div>
            ))
          )}
        </section>
      </OwnerPageContent>

      <Dialog
        open={Boolean(selectedEmployeeId)}
        onOpenChange={(open) => {
          if (!open) setSelectedEmployeeId(null);
        }}
      >
        <DialogContent className="flex max-h-[92vh] max-w-5xl flex-col overflow-hidden">
          <DialogHeader>
            <DialogTitle>Payslip</DialogTitle>
          </DialogHeader>
          <div className="min-h-0 flex-1 overflow-y-auto pr-1">
            {payslipLoading ? (
              <p className="text-sm text-[#6B7280]">Generating payslip...</p>
            ) : payslip ? (
              <div className="grid gap-6 lg:grid-cols-[1fr_280px]">
                <PayslipPreview
                  businessName={businessName}
                  businessLogo={businessLogo}
                  payslip={payslip}
                  settings={payslipSettings}
                />
                {canEditPayslip && (
                  <PayslipEditor
                    settings={payslipSettings}
                    onChange={setPayslipSettings}
                  />
                )}
              </div>
            ) : (
              <p className="text-sm text-[#6B7280]">Payslip not found.</p>
            )}
          </div>
          <DialogFooter className="border-t border-slate-100 pt-4">
            <Button variant="outline" onClick={() => setSelectedEmployeeId(null)}>
              Close
            </Button>
            <Button
              className="gap-2 text-white"
              style={{ backgroundColor: themeButtonColor }}
              disabled={!payslip}
              onClick={() =>
                payslip &&
                downloadPayslip(
                  payslip,
                  businessName,
                  payslipSettings,
                  businessLogo
                )
              }
              onMouseEnter={(event) => {
                event.currentTarget.style.backgroundColor = themeButtonHoverColor;
              }}
              onMouseLeave={(event) => {
                event.currentTarget.style.backgroundColor = themeButtonColor;
              }}
            >
              <Download className="h-4 w-4" />
              Download PDF
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </OwnerPage>
  );
}

function Row({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-center justify-between border-b border-slate-100 pb-2 last:border-b-0">
      <span className="text-[#6B7280]">{label}</span>
      <span className={strong ? "font-semibold text-emerald-700" : "font-medium text-[#1F2937]"}>
        {value}
      </span>
    </div>
  );
}

type PayslipSettings = {
  title: string;
  employeeSection: string;
  earningsSection: string;
  deductionsSection: string;
  netPaySection: string;
  notes: string;
  headerColor: string;
  earningsColor: string;
  deductionsColor: string;
  netColor: string;
};

function PayslipPreview({
  payslip,
  businessName,
  businessLogo,
  settings,
}: {
  payslip: EmployeePayslip;
  businessName: string;
  businessLogo: string | null;
  settings: PayslipSettings;
}) {
  return (
    <div className="mx-auto max-w-md rounded border border-slate-200 bg-white p-6 text-sm shadow-sm">
      <div
        className="mx-auto mb-4 w-44 rounded-full py-2 text-center text-sm font-semibold text-[#374151]"
        style={{ backgroundColor: settings.headerColor }}
      >
        {settings.title}
      </div>
      {businessLogo && (
        <img
          className="mx-auto mb-3 h-14 w-14 rounded-xl object-cover"
          src={businessLogo}
          alt={`${businessName} logo`}
        />
      )}
      <h2 className="border-b border-slate-400 pb-1 text-center text-sm font-semibold">
        {businessName}
      </h2>
      <p className="mt-1 text-center text-xs text-[#6B7280]">Business Name</p>

      <Section title={settings.employeeSection}>
        <Row label="Employee Name" value={payslip.employee_name} />
        <Row label="No. of Working Days" value={`${payslip.worked_days}`} />
        <Row label="Period Date" value={`${payslip.period_start} to ${payslip.period_end}`} />
        <Row label="Position" value={payslip.position_title ?? "Employee"} />
        <Row label="Employment Type" value={payslip.employment_type.replace("_", "-")} />
      </Section>

      <Section title={settings.earningsSection} color={settings.earningsColor}>
        <Row label="Salary Rate (daily)" value={money(payslip.daily_rate)} />
        <Row label="Basic Salary" value={money(payslip.daily_rate * payslip.worked_days)} />
        <Row label="Overtime" value={money(payslip.overtime_pay)} />
        <Row label="Holiday Pay" value={money(payslip.holiday_pay)} />
        <Row label="Total Earnings" value={money(payslip.gross_pay)} strong />
      </Section>

      <Section title={settings.deductionsSection} color={settings.deductionsColor}>
        <Row label="Late/Undertime" value={money(payslip.deductions)} />
        <Row label="Absent Days" value={`${payslip.absent_days}`} />
        <Row label="Total Deductions" value={money(payslip.deductions)} strong />
      </Section>

      <Section title={settings.netPaySection} color={settings.netColor}>
        <Row label="Net Pay" value={money(payslip.net_pay)} strong />
      </Section>
      {settings.notes && (
        <p className="mt-3 text-xs italic text-[#6B7280]">{settings.notes}</p>
      )}
    </div>
  );
}

function Section({
  title,
  children,
  color,
}: {
  title: string;
  children: React.ReactNode;
  color?: string;
}) {
  return (
    <div className="mt-4">
      <div
        className="px-2 py-1 text-xs font-semibold text-[#1F2937]"
        style={{ backgroundColor: color ?? "#E5E7EB" }}
      >
        {title}
      </div>
      <div className="mt-2 space-y-2">{children}</div>
    </div>
  );
}

function PayslipEditor({
  settings,
  onChange,
}: {
  settings: PayslipSettings;
  onChange: (settings: PayslipSettings) => void;
}) {
  function update<K extends keyof PayslipSettings>(
    key: K,
    value: PayslipSettings[K]
  ) {
    onChange({ ...settings, [key]: value });
  }

  return (
    <aside className="rounded-2xl border border-slate-200 bg-[#FAFBFC] p-4">
      <h3 className="text-sm font-semibold text-[#1F2937]">Edit Payslip</h3>
      <p className="mt-1 text-xs text-[#6B7280]">
        Owners can customize labels, notes, and colors. Payroll values remain
        tied to live employee records.
      </p>
      <div className="mt-4 space-y-3">
        <EditorField label="Title" value={settings.title} onChange={(value) => update("title", value)} />
        <EditorField label="Employee Section" value={settings.employeeSection} onChange={(value) => update("employeeSection", value)} />
        <EditorField label="Earnings Section" value={settings.earningsSection} onChange={(value) => update("earningsSection", value)} />
        <EditorField label="Deductions Section" value={settings.deductionsSection} onChange={(value) => update("deductionsSection", value)} />
        <EditorField label="Net Pay Section" value={settings.netPaySection} onChange={(value) => update("netPaySection", value)} />
        <EditorField label="Notes" value={settings.notes} onChange={(value) => update("notes", value)} />
        <ColorField label="Header" value={settings.headerColor} onChange={(value) => update("headerColor", value)} />
        <ColorField label="Earnings" value={settings.earningsColor} onChange={(value) => update("earningsColor", value)} />
        <ColorField label="Deductions" value={settings.deductionsColor} onChange={(value) => update("deductionsColor", value)} />
        <ColorField label="Net Pay" value={settings.netColor} onChange={(value) => update("netColor", value)} />
      </div>
    </aside>
  );
}

function EditorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="block text-xs font-medium text-[#6B7280]">
      {label}
      <Input
        className="mt-1 h-9 bg-white text-sm"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="flex items-center justify-between text-xs font-medium text-[#6B7280]">
      {label}
      <input
        className="h-8 w-10 rounded border border-slate-200 bg-white"
        type="color"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function downloadPayslip(
  payslip: EmployeePayslip,
  businessName: string,
  settings: PayslipSettings,
  businessLogo: string | null
) {
  const doc = new jsPDF();
  let y = 16;
  if (businessLogo?.startsWith("data:image/")) {
    try {
      const imageType = businessLogo.startsWith("data:image/jpeg")
        ? "JPEG"
        : "PNG";
      doc.addImage(businessLogo, imageType, 92, y, 26, 26);
      y += 32;
    } catch {
      // Unsupported image encodings should not block a payroll download.
    }
  }
  doc.setFontSize(16);
  doc.text(settings.title, 105, y, { align: "center" });
  y += 10;
  doc.setFontSize(12);
  doc.text(businessName, 105, y, { align: "center" });
  y += 10;
  doc.setFontSize(10);
  const lines = [
    [settings.employeeSection, ""],
    ["Employee Name", payslip.employee_name],
    ["Position", payslip.position_title ?? "Employee"],
    ["Period", `${payslip.period_start} to ${payslip.period_end}`],
    ["Worked Days", String(payslip.worked_days)],
    [settings.earningsSection, ""],
    ["Daily Rate", money(payslip.daily_rate)],
    ["Basic Salary", money(payslip.daily_rate * payslip.worked_days)],
    ["Overtime Pay", money(payslip.overtime_pay)],
    ["Holiday Pay", money(payslip.holiday_pay)],
    [settings.deductionsSection, ""],
    ["Deductions", money(payslip.deductions)],
    [settings.netPaySection, ""],
    ["Net Pay", money(payslip.net_pay)],
  ];
  for (const [label, value] of lines) {
    if (!value) {
      doc.setFillColor(label === settings.earningsSection ? settings.earningsColor : label === settings.deductionsSection ? settings.deductionsColor : label === settings.netPaySection ? settings.netColor : settings.headerColor);
      doc.rect(20, y - 5, 170, 7, "F");
      doc.setFont(undefined, "bold");
      doc.text(label, 24, y);
      doc.setFont(undefined, "normal");
      y += 9;
      continue;
    }
    doc.text(label, 24, y);
    doc.text(value, 120, y);
    y += 8;
  }
  if (settings.notes) {
    y += 4;
    doc.setFontSize(9);
    doc.text(settings.notes, 24, y);
  }
  doc.save(`${payslip.employee_name.replace(/\s+/g, "-").toLowerCase()}-payslip.pdf`);
}
