# Aroll+ Legal & Consent Templates

**Purpose:** Pilot / thesis **templates** for terms of use, privacy, and biometric consent.

**Status:** Draft templates for the Aroll+ study and pilot businesses. They are **not** formal legal advice and are **not** the runtime source of truth. Have a lawyer review before commercial rollout beyond the academic pilot.

**Runtime source of truth:** Platform Admin publishes default Terms, Privacy, and Biometric Consent. Businesses use those defaults unless an owner sets `use_custom_consents` and publishes custom copy. The app and public webpage (`/legal/b/{business_code}`) render the **effective** content. Unpublished sections cannot be accepted as consent. Acceptance is stored as append-only `consent_record` rows (type + version + content source + snapshot/hash + identity + UTC timestamp), not a single boolean.

| Document | Audience | When to use |
|----------|----------|-------------|
| [TERMS-AND-CONDITIONS.md](TERMS-AND-CONDITIONS.md) | Owners, managers, employees, platform users | Starting copy for the Admin-published default Terms page |
| [PRIVACY-POLICY.md](PRIVACY-POLICY.md) | All users | Starting copy for the Admin-published default Privacy page |
| [BIOMETRIC-CONSENT.md](BIOMETRIC-CONSENT.md) | Employees (face enrollment) | Starting copy for default biometric consent; recorded **before** face enrollment |

**Related technical docs:** [../SECURITY-PLAN.md](../SECURITY-PLAN.md) · [../FACE-RECOGNITION.md](../FACE-RECOGNITION.md) · [../SOLUTION.md](../SOLUTION.md)

## How to use in the pilot

1. Platform Admin publishes default Terms, Privacy, and Biometric Consent (content + version). Owners may optionally enable custom workplace copy in Business Settings. The generated workplace URL is what employees open.
2. Employee first login: temporary password change → Terms + Privacy webpage → recorded acceptance → permission rationale → biometric consent → face enrollment / live attendance.
3. Policy version changes require re-consent. An Admin default version bump affects only businesses using defaults. Biometric withdrawal and employee deactivation clear that employee’s face embeddings.
4. `consent_record` is the legal audit source of truth; activity logs are operational.

## Placeholders to fill per deployment

Replace these in the **Admin-published defaults** (or in a business custom override). These markdown files stay as templates:

- `[ORGANIZATION NAME]` — thesis team / hosting entity name  
- `[CONTACT EMAIL]` — privacy / support contact  
- `[EFFECTIVE DATE]` — go-live date  
- `[PILOT END DATE]` — expected end of UAT/pilot (if fixed)  
- `[BUSINESS NAME]` — participating employer (consent form)
