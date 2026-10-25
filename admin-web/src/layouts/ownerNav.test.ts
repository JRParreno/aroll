/**
 * Run: npx --yes tsx --test src/layouts/ownerNav.test.ts
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isOwnerNavItemActive, ownerNavItems } from "./ownerNav.ts";

describe("owner navigation", () => {
  it("places Setup Summary after Settings and before Help", () => {
    const labels = ownerNavItems.map((item) => item.label);
    const settings = labels.indexOf("Settings");
    const summary = labels.indexOf("Setup Summary");
    const help = labels.indexOf("Help");
    assert.equal(summary, settings + 1);
    assert.equal(help, summary + 1);
    assert.equal(
      ownerNavItems[summary].to,
      "/owner/settings/setup-summary"
    );
  });

  it("highlights Setup Summary without also highlighting Settings", () => {
    const settings = ownerNavItems.find((item) => item.label === "Settings");
    const summary = ownerNavItems.find((item) => item.label === "Setup Summary");
    assert.ok(settings);
    assert.ok(summary);
    assert.equal(
      isOwnerNavItemActive(
        "/owner/settings/setup-summary",
        summary.to,
        summary.activePaths
      ),
      true
    );
    assert.equal(
      isOwnerNavItemActive(
        "/owner/settings/setup-summary",
        settings.to,
        settings.activePaths
      ),
      false
    );
    assert.equal(
      isOwnerNavItemActive(
        "/owner/settings/business",
        settings.to,
        settings.activePaths
      ),
      true
    );
    assert.equal(
      isOwnerNavItemActive("/owner/help", "/owner/help"),
      true
    );
  });
});
