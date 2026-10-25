/**
 * Run: node --test src/lib/scheduleAssignmentDeletion.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SCHEDULE_REMOVAL_FALLBACK,
  scheduleRemovalErrorMessage,
} from "./scheduleAssignmentDeletion.ts";

const openMessage =
  "This schedule cannot be removed because the employee is currently timed in. Ask them to complete Time Out, then try again.";

describe("schedule assignment deletion errors", () => {
  it("shows the backend detail when removal is rejected", () => {
    const message = scheduleRemovalErrorMessage({
      response: { status: 409, data: { detail: openMessage } },
    });
    assert.equal(message, openMessage);
    assert.match(message, /Time Out/);
  });

  it("shows a structured detail message", () => {
    assert.equal(
      scheduleRemovalErrorMessage({
        response: {
          data: { detail: { message: "Attendance has already been recorded." } },
        },
      }),
      "Attendance has already been recorded."
    );
  });

  it("keeps the generic fallback when the server sends no usable message", () => {
    assert.equal(scheduleRemovalErrorMessage(new Error("network")), SCHEDULE_REMOVAL_FALLBACK);
    assert.equal(
      scheduleRemovalErrorMessage({ response: { data: { detail: "  " } } }),
      SCHEDULE_REMOVAL_FALLBACK
    );
    assert.equal(
      scheduleRemovalErrorMessage({ response: { data: {} } }),
      SCHEDULE_REMOVAL_FALLBACK
    );
  });
});
