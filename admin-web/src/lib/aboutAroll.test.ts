/**
 * Run: node --test src/lib/aboutAroll.test.ts
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  ABOUT_AROLL_INTRO,
  ABOUT_AROLL_TITLE,
  ABOUT_DOWNLOAD_TEXT,
  aboutDialogOpenAfter,
  ANDROID_APK_URL,
  groupFeatureCards,
} from "./aboutAroll.ts";
import { apkQrSvg } from "./apkQr.ts";

const featureSource = readFileSync(
  new URL("../components/marketing/OwnerPublicChrome.tsx", import.meta.url),
  "utf8"
);

function featureTitles(): string[] {
  return [...featureSource.matchAll(/title: "([^"]+)"/g)].map((match) => match[1]);
}

describe("About Aroll+ dialog content", () => {
  it("introduces attendance and payroll without a QR code", () => {
    assert.equal(ABOUT_AROLL_TITLE, "About Aroll+");
    assert.match(ABOUT_AROLL_INTRO, /attendance/i);
    assert.match(ABOUT_AROLL_INTRO, /payroll/i);
    assert.equal(/qr/i.test(`${ABOUT_AROLL_INTRO} ${ABOUT_DOWNLOAD_TEXT}`), false);
  });

  it("groups every feature from the features page exactly once", () => {
    const titles = featureTitles();
    const groups = groupFeatureCards(titles.map((title) => ({ title })));
    const shown = groups.flatMap((group) => group.features.map((feature) => feature.title));
    assert.deepEqual(shown, [
      "Attendance monitoring",
      "Employee management",
      "Positions and pay rates",
      "Schedules and shifts",
      "Workplace location",
      "Payroll",
      "Leave",
      "Notifications",
    ]);
    assert.deepEqual([...shown].sort(), [...titles].sort());
    assert.equal(groups[0]?.label, "Employee Mobile App");
    assert.equal(groups[1]?.label, "Business Owner Management");
  });

  it("points the Android download at the published APK URL", () => {
    assert.equal(ANDROID_APK_URL, "https://arollplus.duckdns.org/aroll.apk");
  });

  it("shows the dialog on open and hides it for every dismissal", () => {
    assert.equal(aboutDialogOpenAfter("open"), true);
    assert.equal(aboutDialogOpenAfter("close-button"), false);
    assert.equal(aboutDialogOpenAfter("escape"), false);
    assert.equal(aboutDialogOpenAfter("outside-click"), false);
  });

  it("encodes the Android APK URL in a square QR symbol", () => {
    const { svg, payload } = apkQrSvg(ANDROID_APK_URL);
    assert.equal(payload, "https://arollplus.duckdns.org/aroll.apk");
    const viewBox = svg.match(/viewBox="0 0 (\d+) (\d+)"/);
    assert.ok(viewBox);
    assert.equal(viewBox[1], viewBox[2]);
    assert.match(svg, /fill="#172554"/);
    assert.match(svg, /fill="#FFFFFF"/);
    assert.equal(svg.includes("rx="), false);
  });
});
