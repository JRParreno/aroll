/**
 * Run: node --test src/lib/shiftDeletion.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SHIFT_DELETE_BLOCKED_MESSAGE,
  shiftDeleteBlockedMessage,
} from "./shiftDeletion.ts";

function blockedError() {
  return {
    response: {
      status: 409,
      data: {
        detail: {
          code: "shift_delete_blocked",
          title: "Cannot delete shift",
          message: SHIFT_DELETE_BLOCKED_MESSAGE,
        },
      },
    },
  };
}

describe("shift deletion rejection", () => {
  it("shows the backend message when an employee is still timed in", () => {
    assert.equal(shiftDeleteBlockedMessage(blockedError()), SHIFT_DELETE_BLOCKED_MESSAGE);
    assert.match(SHIFT_DELETE_BLOCKED_MESSAGE, /currently timed in/);
    assert.match(SHIFT_DELETE_BLOCKED_MESSAGE, /Time Out/);
  });

  it("does not treat a completed-shift or other error as this restriction", () => {
    assert.equal(shiftDeleteBlockedMessage(new Error("network")), null);
    assert.equal(
      shiftDeleteBlockedMessage({
        response: { data: { detail: { code: "shift_in_progress", message: "started" } } },
      }),
      null
    );
  });
});
