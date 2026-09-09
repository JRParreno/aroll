import termsMarkdown from "../../../docs/legal/TERMS-AND-CONDITIONS.md?raw";
import privacyMarkdown from "../../../docs/legal/PRIVACY-POLICY.md?raw";
import biometricMarkdown from "../../../docs/legal/BIOMETRIC-CONSENT.md?raw";

export type LegalDocumentSlug = "terms" | "privacy" | "biometric-consent";

export type LegalDocument = {
  slug: LegalDocumentSlug;
  title: string;
  markdown: string;
};

export const LEGAL_DOCUMENTS: Record<LegalDocumentSlug, LegalDocument> = {
  terms: {
    slug: "terms",
    title: "Terms & Conditions",
    markdown: termsMarkdown,
  },
  privacy: {
    slug: "privacy",
    title: "Privacy Policy",
    markdown: privacyMarkdown,
  },
  "biometric-consent": {
    slug: "biometric-consent",
    title: "Biometric / Face Consent",
    markdown: biometricMarkdown,
  },
};

export function legalPlainText(markdown: string) {
  return markdown.replace(/^#+\s*/gm, "").replace(/\*\*/g, "").trim();
}
