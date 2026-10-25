# Aroll+ Legal & Consent Templates

**Purpose:** Pilot / thesis **templates** for terms of use, privacy, and biometric consent.

**Status:** Draft templates for the Aroll+ study and pilot businesses. They are **not** formal legal advice and are **not** the runtime source of truth. Have a lawyer review before commercial rollout beyond the academic pilot.

**Runtime source of truth:** The official default wording is the version-controlled text in `backend/app/legal_defaults/` (`terms.txt`, `privacy.txt`, `biometric.txt`). Application startup and `python -m app.seed` copy that wording into the platform consent records when a record is missing, unpublished, or still an unedited system default. A platform document an administrator has edited is left as saved. Businesses with custom consents keep their own documents. Web and mobile read those database records; they do not keep a separate copy of the text. These markdown files are templates and are not what the app displays. Acceptance is stored as append-only `consent_record` rows (type + version + content source + snapshot/hash + identity + UTC timestamp), not a single boolean.

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
