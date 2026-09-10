# Aroll+ Legal & Consent Templates

**Purpose:** Pilot / thesis **templates** for terms of use, privacy, and biometric consent.

**Status:** Draft templates for the Aroll+ study and pilot businesses. They are **not** formal legal advice and are **not** the runtime source of truth. Have a lawyer review before commercial rollout beyond the academic pilot.

**Runtime source of truth:** each owner publishes Terms, Privacy, and Biometric Consent in **Business Settings**. The app and public webpage (`/legal/b/{business_code}`) render that owner-configured content. Unpublished sections cannot be accepted as consent. Acceptance is stored as append-only `consent_record` rows (type + version + identity + UTC timestamp), not a single boolean.

| Document | Audience | When to use |
|----------|----------|-------------|
| [TERMS-AND-CONDITIONS.md](TERMS-AND-CONDITIONS.md) | Owners, managers, employees, platform users | Starting copy for the owner-published Terms page |
| [PRIVACY-POLICY.md](PRIVACY-POLICY.md) | All users | Starting copy for the owner-published Privacy page |
| [BIOMETRIC-CONSENT.md](BIOMETRIC-CONSENT.md) | Employees (face enrollment) | Starting copy for biometric consent; recorded **before** face enrollment |

**Related technical docs:** [../SECURITY-PLAN.md](../SECURITY-PLAN.md) · [../FACE-RECOGNITION.md](../FACE-RECOGNITION.md) · [../SOLUTION.md](../SOLUTION.md)

## How to use in the pilot

1. Owner pastes or adapts these templates in Business Settings, sets a version id, and publishes. The generated workplace URL is what employees open.
2. Employee first login: temporary password change → Terms + Privacy webpage → recorded acceptance → permission rationale → biometric consent → face enrollment / live attendance.
3. Policy version changes require re-consent. Biometric withdrawal and employee deactivation clear that employee’s face embeddings.
4. `consent_record` is the legal audit source of truth; activity logs are operational.

## Placeholders to fill per deployment

Replace these in the owner-published Business Settings copy (these markdown files stay as templates):

- `[ORGANIZATION NAME]` — thesis team / hosting entity name  
- `[CONTACT EMAIL]` — privacy / support contact  
- `[EFFECTIVE DATE]` — go-live date  
- `[PILOT END DATE]` — expected end of UAT/pilot (if fixed)  
- `[BUSINESS NAME]` — participating employer (consent form)
