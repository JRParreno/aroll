/** Copy and grouping for the Business Owner Login “About Aroll+” dialog. */

export const ABOUT_AROLL_TITLE = "About Aroll+";

export const ABOUT_AROLL_INTRO =
  "Aroll+ helps small businesses manage employee attendance and payroll.";

export const ABOUT_DOWNLOAD_TEXT =
  "Install the Android app for face recognition attendance, shift history, payroll, and owner tools on a phone.";

export const ANDROID_APK_URL = "https://arollplus.duckdns.org/aroll.apk";

/**
 * Titles from `ownerFeatureCards`. Employee vs owner follows the existing
 * card wording: attendance is the employee flow; the rest are owner tools.
 */
export const ABOUT_FEATURE_GROUPS = [
  {
    id: "employee",
    label: "Employee Mobile App",
    titles: ["Attendance monitoring"],
  },
  {
    id: "owner",
    label: "Business Owner Management",
    titles: [
      "Employee management",
      "Positions and pay rates",
      "Schedules and shifts",
      "Workplace location",
      "Payroll",
      "Leave",
      "Notifications",
    ],
  },
] as const;

export type AboutDialogEvent =
  | "open"
  | "close-button"
  | "escape"
  | "outside-click";

/** Open shows the dialog. Close, Escape, and an outside click hide it. */
export function aboutDialogOpenAfter(event: AboutDialogEvent): boolean {
  return event === "open";
}

export function groupFeatureCards<T extends { title: string }>(
  cards: readonly T[]
): { id: string; label: string; features: T[] }[] {
  const byTitle = new Map(cards.map((card) => [card.title, card]));
  const used = new Set<string>();
  const groups = ABOUT_FEATURE_GROUPS.map((group) => ({
    id: group.id,
    label: group.label,
    features: group.titles.map((title) => {
      const card = byTitle.get(title);
      if (!card) {
        throw new Error(`About Aroll+ is missing the feature “${title}”.`);
      }
      used.add(title);
      return card;
    }),
  }));
  const extra = cards.filter((card) => !used.has(card.title)).map((card) => card.title);
  if (extra.length > 0) {
    throw new Error(`About Aroll+ has no group for: ${extra.join(", ")}.`);
  }
  return groups;
}
