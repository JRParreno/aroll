# Aroll+ legal and consent documents

These markdown files are **project documentation / reference** for the Aroll+ thesis prototype. They are **not** the runtime source of employee consent.

Employee consent is:

1. Configured per business in **Business Settings** (owner portal)
2. Published as a generated webpage at `/legal/b/{business_code}`
3. Recorded on the employee profile (`legal_consent_accepted`) when the employee agrees in the mobile app

| Document | File | Role |
|----------|------|------|
| Terms & Conditions | [TERMS-AND-CONDITIONS.md](./TERMS-AND-CONDITIONS.md) | Prototype reference |
| Privacy Policy | [PRIVACY-POLICY.md](./PRIVACY-POLICY.md) | Prototype reference |
| Biometric / face consent | [BIOMETRIC-CONSENT.md](./BIOMETRIC-CONSENT.md) | Prototype reference |

Login screens may still link to these reference documents. After an employee logs in, consent uses the workplace-configured webpage and the database flag.
