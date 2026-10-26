/**
 * Run: node --test src/lib/supportEmail.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SUPPORT_EMAIL,
  SUPPORT_MESSAGE_MAX,
  claimSupportSubmit,
  supportRequestErrorMessage,
  validateSupportDraft,
} from "./supportEmail.ts";

describe("owner help support email", () => {
  it("requires a subject and a message", () => {
    assert.equal(validateSupportDraft("  ", "The scanner failed."), "Enter a subject.");
    assert.equal(validateSupportDraft("Scanner", "   "), "Enter the concern or message.");
    assert.equal(validateSupportDraft("Scanner", "The scanner failed."), null);
  });

  it("rejects a message past the limit", () => {
    const result = validateSupportDraft("Scanner", "x".repeat(SUPPORT_MESSAGE_MAX + 1));
    assert.match(result ?? "", /4000/);
  });

  it("keeps the support address fixed in the client helper", () => {
    assert.equal(SUPPORT_EMAIL, "arollplus1111@gmail.com");
  });

  it("shows the provider acceptance detail and hides internal errors", () => {
    const accepted = supportRequestErrorMessage({
      response: {
        data: {
          detail: "The email provider could not accept the message.",
        },
      },
    });
    assert.match(accepted, /could not accept/);

    const leaked = supportRequestErrorMessage({
      response: { data: { detail: "SMTP password rejected: Traceback" } },
    });
    assert.doesNotMatch(leaked, /password|Traceback|SMTP/i);
    assert.match(leaked, /could not be sent/);
  });

  it("ignores a second submit while the first is still running", () => {
    const inFlight = { current: false };
    assert.equal(claimSupportSubmit(inFlight), true);
    assert.equal(claimSupportSubmit(inFlight), false);
    inFlight.current = false;
    assert.equal(claimSupportSubmit(inFlight), true);
  });
});
