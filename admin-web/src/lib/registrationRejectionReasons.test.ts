/**
 * Rejection checklist helpers.
 * Run: npx --yes tsx --test src/lib/registrationRejectionReasons.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  OTHER_REJECTION_REASON_ID,
  REGISTRATION_REJECTION_REASONS,
  buildRejectionPayload,
  canConfirmRejection,
  toggleRejectionReason,
} from "./registrationRejectionReasons.ts";

describe("registration rejection checklist", () => {
  it("defines the admin checklist options", () => {
    const labels = REGISTRATION_REJECTION_REASONS.map((item) => item.label);
    assert.equal(REGISTRATION_REJECTION_REASONS.length, 10);
    assert.ok(labels.includes("Required documents are missing."));
    assert.ok(
      labels.includes("Other reason — requires a short explanation.")
    );
  });

  it("allows selecting multiple reasons independently", () => {
    let selected: string[] = [];
    selected = toggleRejectionReason(selected, "missing_documents");
    selected = toggleRejectionReason(selected, "incomplete_documents");
    assert.deepEqual(selected, [
      "missing_documents",
      "incomplete_documents",
    ]);
    selected = toggleRejectionReason(selected, "missing_documents");
    assert.deepEqual(selected, ["incomplete_documents"]);
  });

  it("disables confirmation when no reasons are selected", () => {
    assert.equal(canConfirmRejection([], ""), false);
    assert.equal(canConfirmRejection(["missing_documents"], ""), true);
  });

  it("requires a non-empty Other explanation", () => {
    assert.equal(canConfirmRejection([OTHER_REJECTION_REASON_ID], "   "), false);
    assert.equal(
      canConfirmRejection([OTHER_REJECTION_REASON_ID], "Permit photo is cropped"),
      true
    );
  });

  it("omits Other explanation unless Other is selected", () => {
    const withoutOther = buildRejectionPayload(
      ["missing_documents"],
      "should be ignored"
    );
    assert.deepEqual(withoutOther, { reasons: ["missing_documents"] });
    const withOther = buildRejectionPayload(
      ["missing_documents", OTHER_REJECTION_REASON_ID],
      "  Permit photo is cropped  "
    );
    assert.deepEqual(withOther, {
      reasons: ["missing_documents", OTHER_REJECTION_REASON_ID],
      other_explanation: "Permit photo is cropped",
    });
  });
});
