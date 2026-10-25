import type { ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  OwnerCard,
  OwnerPage,
  OwnerPageBackLink,
  OwnerPageContent,
  OwnerPageHeader,
} from "@/components/owner/layout/OwnerPageLayout";
import { Button } from "@/components/ui/button";
import {
  getAttendancePolicy,
  getBusinessLocation,
  getBusinessSettings,
  getPayrollConfig,
  getRestDayPolicy,
  listHolidays,
  listPositions,
  listShifts,
} from "@/lib/api";
import {
  buildSetupSummarySections,
  isUnconfiguredSummaryValue,
  summaryPositionItems,
  summaryShiftItems,
  type SetupSummaryInput,
  type SetupSummaryRow,
  type SetupSummarySection,
  type SummaryListItem,
} from "@/lib/setupSummaryDisplay";
import { cn } from "@/lib/utils";

type SetupSummaryView = {
  input: SetupSummaryInput;
  sections: SetupSummarySection[];
};

async function loadSetupSummary(): Promise<SetupSummaryView> {
  const [
    business,
    location,
    shifts,
    positions,
    payroll,
    attendancePolicy,
    holidays,
    restDayPolicy,
  ] = await Promise.all([
    getBusinessSettings(),
    getBusinessLocation(),
    listShifts(),
    listPositions(),
    getPayrollConfig(),
    getAttendancePolicy(),
    listHolidays(),
    getRestDayPolicy(),
  ]);

  const input: SetupSummaryInput = {
    business,
    location,
    shifts,
    positions,
    payroll,
    attendancePolicy,
    holidays,
    restDayPolicy,
  };

  return { input, sections: buildSetupSummarySections(input) };
}

function sectionRows(sections: SetupSummarySection[], title: string) {
  return sections.find((section) => section.title === title)?.rows ?? [];
}

export function OwnerSetupSummaryPage() {
  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["owner-setup-summary"],
    queryFn: loadSetupSummary,
  });

  return (
    <OwnerPage>
      <OwnerPageHeader
        back={
          <OwnerPageBackLink to="/owner/settings/setup" label="Business Setup" />
        }
        eyebrow="Business setup"
        title="Setup Summary"
        description="Review the business setup saved for this workplace. This page only displays your current configuration."
        actions={
          <Button
            type="button"
            variant="outline"
            className="rounded-xl"
            onClick={() => void refetch()}
            disabled={isFetching}
          >
            Refresh
          </Button>
        }
      />
      <OwnerPageContent>
        {isLoading ? (
          <OwnerCard className="px-4 py-3.5">
            <p className="text-sm font-normal text-[#6B7280]">Loading setup summary…</p>
          </OwnerCard>
        ) : isError || !data ? (
          <OwnerCard className="px-4 py-3.5">
            <p className="text-sm text-[#6B7280]">
              Unable to load setup summary. Your saved setup was not changed.
            </p>
            <Button className="mt-3 rounded-xl" onClick={() => void refetch()}>
              Retry
            </Button>
          </OwnerCard>
        ) : (
          <SummaryBoard view={data} />
        )}
      </OwnerPageContent>
    </OwnerPage>
  );
}

function SummaryBoard({ view }: { view: SetupSummaryView }) {
  const shifts = summaryShiftItems(view.input.shifts);
  const positions = summaryPositionItems(view.input.positions);

  return (
    <div className="space-y-8">
      <SummarySection title="Business Profile">
        <FactPanel rows={sectionRows(view.sections, "Business Profile")} columns="xl:grid-cols-4" />
      </SummarySection>
      <SummarySection title="Work Location">
        <FactPanel rows={sectionRows(view.sections, "Work Location")} columns="lg:grid-cols-3" />
      </SummarySection>
      <SummarySection title="Work Shifts">
        <ItemBoard items={shifts} emptyLabel="None configured" />
      </SummarySection>
      <SummarySection title="Employee Positions">
        <ItemBoard items={positions} emptyLabel="None configured" />
      </SummarySection>
      <SummarySection title="Payroll">
        <FactPanel rows={sectionRows(view.sections, "Payroll")} columns="lg:grid-cols-3" />
      </SummarySection>
      <SummarySection title="Attendance">
        <FactPanel rows={sectionRows(view.sections, "Attendance")} columns="lg:grid-cols-3" />
      </SummarySection>
      <div className="grid items-start gap-8 lg:grid-cols-2 lg:gap-6">
        <SummarySection title="Holidays">
          <FactPanel
            rows={sectionRows(view.sections, "Holidays")}
            columns="sm:grid-cols-1"
          />
        </SummarySection>
        <SummarySection title="Rest Days">
          <FactPanel
            rows={sectionRows(view.sections, "Rest Days")}
            columns="sm:grid-cols-1"
          />
        </SummarySection>
      </div>
    </div>
  );
}

const summaryCardClass =
  "min-w-0 rounded-lg border border-slate-200/90 bg-white px-4 py-3.5";

function SummarySection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="min-w-0">
      <h2 className="mb-3 text-base font-semibold tracking-tight text-[var(--owner-ink)]">
        {title}
      </h2>
      {children}
    </section>
  );
}

function FactPanel({
  rows,
  columns = "lg:grid-cols-3",
}: {
  rows: SetupSummaryRow[];
  columns?: string;
}) {
  return (
    <div className={cn("grid grid-cols-1 items-start gap-3 sm:grid-cols-2", columns)}>
      {rows.map((row) => (
        <article
          key={row.label}
          className={cn(
            summaryCardClass,
            row.label === "Workplace Address" && "sm:col-span-2 lg:col-span-3"
          )}
        >
          <p className="text-xs font-normal leading-5 text-[var(--owner-muted)]">
            {row.label}
          </p>
          <p className="mt-1.5 break-words text-sm font-medium leading-5">
            <FactValue label={row.label} value={row.value} />
          </p>
        </article>
      ))}
    </div>
  );
}

function FactValue({ label, value }: { label: string; value: string }) {
  const missing = isUnconfiguredSummaryValue(value);
  const isStatus =
    label === "Business Status" ||
    label === "Work Location Validation" ||
    label === "Work Location Validation Status" ||
    label === "Time-In Settings";
  const positive = value === "Enabled" || value === "Configured";

  return (
    <span
      className={cn(
        isStatus && positive && "text-[var(--owner-navy)]",
        (missing || (isStatus && !positive)) && "font-normal text-[var(--owner-muted)]",
        !isStatus && !missing && "text-[var(--owner-ink)]"
      )}
    >
      {value}
    </span>
  );
}

function ItemBoard({
  items,
  emptyLabel,
}: {
  items: SummaryListItem[];
  emptyLabel: string;
}) {
  if (items.length === 0) {
    return (
      <article className={summaryCardClass}>
        <p className="text-sm font-normal text-[var(--owner-muted)]">{emptyLabel}</p>
      </article>
    );
  }

  return (
    <div className="grid grid-cols-1 items-start gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {items.map((item, index) => (
        <article key={`${item.name}-${index}`} className={summaryCardClass}>
          <p className="break-words text-sm font-medium leading-5 text-[var(--owner-ink)]">
            {item.name}
          </p>
          {item.detail ? (
            <p className="mt-1.5 break-words text-xs font-normal leading-5 text-[var(--owner-muted)]">
              {item.detail}
            </p>
          ) : null}
        </article>
      ))}
    </div>
  );
}
