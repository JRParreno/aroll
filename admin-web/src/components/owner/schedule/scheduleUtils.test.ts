/**
 * Schedule Library date helpers used by Owner Web weekly/today views.
 * Run: npx --yes tsx --test src/components/owner/schedule/scheduleUtils.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  assignmentDateKey,
  assignmentsOnDate,
  buildScheduleMatrix,
  employeesWithScheduleAssignments,
  getWeekStart,
  restDayPremiumInitialValue,
  scheduleRangeError,
  templateApplyRange,
  toDateKey,
} from "./scheduleUtils.ts";

describe("assignmentDateKey", () => {
  it("keeps yyyy-MM-dd keys unchanged", () => {
    assert.equal(assignmentDateKey("2026-10-01"), "2026-10-01");
  });

  it("strips ISO datetime suffixes so today's schedule still matches", () => {
    assert.equal(assignmentDateKey("2026-10-01T00:00:00"), "2026-10-01");
    assert.equal(assignmentDateKey("2026-10-01T16:00:00.000Z"), "2026-10-01");
  });
});

describe("getWeekStart", () => {
  it("uses Monday as the week start, including mid-week dates", () => {
    assert.equal(toDateKey(getWeekStart(new Date(2026, 8, 24))), "2026-09-21");
    assert.equal(toDateKey(getWeekStart(new Date(2026, 8, 21))), "2026-09-21");
  });

  it("crosses month and year boundaries on Monday", () => {
    assert.equal(toDateKey(getWeekStart(new Date(2026, 9, 1))), "2026-09-28");
    assert.equal(toDateKey(getWeekStart(new Date(2027, 0, 1))), "2026-12-28");
  });
});

describe("scheduleRangeError", () => {
  it("allows a single date and a forward range", () => {
    assert.equal(scheduleRangeError("2026-10-19", "2026-10-19"), null);
    assert.equal(scheduleRangeError("2026-10-19", "2026-10-25"), null);
  });

  it("rejects an end date before the start date", () => {
    assert.equal(
      scheduleRangeError("2026-10-25", "2026-10-19"),
      "End date must be the same as or later than the start date."
    );
  });

  it("keeps the library range even when the calendar is on another date", () => {
    assert.deepEqual(templateApplyRange("2026-11-02", "2026-11-06"), {
      start_date: "2026-11-02",
      end_date: "2026-11-06",
    });
  });
});

describe("restDayPremiumInitialValue", () => {
  it("starts unchecked so Add Employee can set premium independently of a template", () => {
    assert.equal(restDayPremiumInitialValue(), false);
  });
});

describe("assignmentsOnDate", () => {
  it("keeps yyyy-MM-dd and ISO datetime assignments on the selected date", () => {
    const assignments = [
      { id: "plain", work_date: "2026-10-01", employee_id: "emp-1" },
      { id: "iso", work_date: "2026-10-01T16:00:00.000Z", employee_id: "emp-2" },
      { id: "other", work_date: "2026-10-02", employee_id: "emp-3" },
    ] as never;
    const today = assignmentsOnDate(assignments, "2026-10-01");
    assert.deepEqual(
      today.map((row) => row.id),
      ["plain", "iso"]
    );
    assert.equal(assignmentsOnDate(assignments, "2026-10-03").length, 0);
  });
});

describe("employeesWithScheduleAssignments", () => {
  it("appends assigned employees who are missing from the listed roster", () => {
    const listed = [{ id: "emp-1", full_name: "Ana Cruz" }] as never;
    const assignments = [
      { employee_id: "emp-1", employee_name: "Ana Cruz" },
      { employee_id: "emp-2", employee_name: "Ben Reyes" },
    ] as never;
    const merged = employeesWithScheduleAssignments(listed, assignments);
    assert.equal(merged.length, 2);
    assert.equal(merged[1].id, "emp-2");
    assert.equal(merged[1].full_name, "Ben Reyes");
  });
});

describe("buildScheduleMatrix", () => {
  it("places copied assignments on the matching weekday even when work_date is ISO", () => {
    const employees = [{ id: "emp-1", full_name: "Ana Cruz" }] as never;
    const assignments = [
      {
        id: "asg-1",
        employee_id: "emp-1",
        work_date: "2026-10-01T00:00:00.000Z",
        shift_id: "shift-1",
      },
    ] as never;
    const matrix = buildScheduleMatrix(
      employees,
      assignments,
      getWeekStart(new Date(2026, 8, 28))
    );
    const thursday = matrix[0].cells[3];
    assert.equal(thursday.length, 1);
    assert.equal(thursday[0].id, "asg-1");
  });

  it("shows a multi-weekday template's employees on every Nov 2-6 date after refresh", () => {
    const dates = [
      "2026-11-02",
      "2026-11-03",
      "2026-11-04",
      "2026-11-05",
      "2026-11-06",
    ];
    const assignments = dates.flatMap((work_date) => [
      {
        id: `aina-${work_date}`,
        employee_id: "emp-aina",
        employee_name: "Aina Bejer",
        work_date,
        shift_id: "morning",
        is_rest_day_work: false,
      },
      {
        id: `ali-${work_date}`,
        employee_id: "emp-ali",
        employee_name: "Ali Cornal",
        work_date: `${work_date}T00:00:00.000Z`,
        shift_id: "evening",
        is_rest_day_work: false,
      },
    ]) as never;
    for (const day of dates) {
      assert.equal(assignmentsOnDate(assignments, day).length, 2);
    }
    const matrix = buildScheduleMatrix(
      employeesWithScheduleAssignments([], assignments),
      assignments,
      getWeekStart(new Date(2026, 10, 2))
    );
    for (const index of [0, 1, 2, 3, 4]) {
      assert.equal(matrix[0].cells[index].length, 1);
      assert.equal(matrix[1].cells[index].length, 1);
    }
  });

  it("shows refreshed assignments on every Nov 2-6 date after a weekly reload", () => {
    const dates = [
      "2026-11-02",
      "2026-11-03",
      "2026-11-04",
      "2026-11-05",
      "2026-11-06",
    ];
    const assignments = dates.flatMap((work_date) => [
      {
        id: `ana-${work_date}`,
        employee_id: "emp-1",
        employee_name: "Ana Cruz",
        work_date,
        shift_id: "morning",
      },
      {
        id: `ben-${work_date}`,
        employee_id: "emp-2",
        employee_name: "Ben Reyes",
        work_date: `${work_date}T00:00:00.000Z`,
        shift_id: "afternoon",
      },
    ]) as never;
    for (const day of dates) {
      const rows = assignmentsOnDate(assignments, day);
      assert.equal(rows.length, 2);
      assert.deepEqual(
        rows.map((row) => row.employee_name).sort(),
        ["Ana Cruz", "Ben Reyes"]
      );
    }
    const weekStart = getWeekStart(new Date(2026, 10, 2));
    assert.equal(toDateKey(weekStart), "2026-11-02");
    const matrix = buildScheduleMatrix(
      employeesWithScheduleAssignments([], assignments),
      assignments,
      weekStart
    );
    assert.equal(matrix.length, 2);
    for (const index of [0, 1, 2, 3, 4]) {
      assert.equal(matrix[0].cells[index].length, 1);
      assert.equal(matrix[1].cells[index].length, 1);
    }
    assert.equal(matrix[0].cells[5].length, 0);
    assert.equal(matrix[0].cells[6].length, 0);
  });

  it("keeps assignment-only employees visible across month boundaries", () => {
    const assignments = [
      {
        id: "asg-2",
        employee_id: "emp-9",
        employee_name: "Cara Lim",
        work_date: "2026-10-01",
        shift_id: "shift-1",
      },
    ] as never;
    const matrix = buildScheduleMatrix(
      employeesWithScheduleAssignments([], assignments),
      assignments,
      getWeekStart(new Date(2026, 8, 28))
    );
    assert.equal(matrix.length, 1);
    assert.equal(matrix[0].employee.full_name, "Cara Lim");
    assert.equal(matrix[0].cells[3].length, 1);
    assert.equal(matrix[0].cells[0].length, 0);
  });
});
