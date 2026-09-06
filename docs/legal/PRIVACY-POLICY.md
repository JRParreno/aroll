# Aroll+ Privacy Policy

**Effective date:** `[EFFECTIVE DATE]`  
**Data controller / operator (pilot):** `[ORGANIZATION NAME]`  
**Privacy contact:** `[CONTACT EMAIL]`  
**Pilot period (if applicable):** until `[PILOT END DATE]`

This Privacy Policy explains how Aroll+ collects, uses, stores, and shares personal data when you use the mobile app, admin web, or APIs during the academic / pilot deployment.

We process personal data in line with the Philippine **Data Privacy Act of 2012 (Republic Act No. 10173)** and its implementing rules, as applicable to this pilot.

---

## 1. Who this applies to

- Business owners and managers  
- Employees of participating businesses  
- Platform administrators  
- Persons who submit a business registration request  

Participating **employers** may also act as personal information controllers for employment data they decide to process using Aroll+. `[ORGANIZATION NAME]` operates the platform and processes data to provide the service and conduct the thesis/pilot evaluation.

---

## 2. Data we collect

### 2.1 Account and profile

- Name, email address, phone (where provided)  
- Role (platform admin, owner, manager, employee)  
- Business affiliation (`business_id`)  
- Password (stored as a **one-way hash**, not plaintext)  
- Login timestamps and account status  

### 2.2 Business registration

- Business name and proposed address  
- Owner identity and contact details  
- Uploaded registration documents (e.g. permits / IDs as required by the pilot onboarding flow)  
- Approval / rejection status and review notes  

### 2.3 Employment and workforce

- Employee code, position, hire date, pay-related configuration used by the business  
- Shift assignments and schedules  
- Attendance records (time in/out, status, location used for geofence checks)  
- Payroll runs and payslip data generated in the system  

### 2.4 Biometric-related data

- Face images captured **during enrollment and clock-in** (processed on the server)  
- **Face embeddings** (numeric templates) stored for matching — not intended as a photo gallery  
- Liveness challenge results and face match scores associated with attendance events  
- Design goal: **do not retain raw face images long-term**; embeddings are kept for verification  

See also [BIOMETRIC-CONSENT.md](BIOMETRIC-CONSENT.md).

### 2.5 Location data

- GPS coordinates submitted at clock-in/out to check presence within the employer’s configured geofence  
- Workplace address and geofence settings configured by the business  

### 2.6 Technical logs

- API request metadata needed for security, debugging, and reliability (e.g. error codes, approximate time of request)  
- Device/app information reasonably needed to operate the mobile client  

We do **not** sell personal data.

---

## 3. Why we use the data (purposes)

| Purpose | Examples |
|---------|----------|
| Provide the service | Login, RBAC, tenant isolation, shifts, attendance, payslips |
| Verify identity at clock-in | Face match + liveness + geofence |
| Business onboarding | Registration review and approval |
| Security | Detect abuse, protect accounts, investigate incidents |
| Pilot / thesis evaluation | Aggregate reliability and functional suitability metrics (ISO 25010–oriented), preferably de-identified where possible |
| Legal compliance | Respond to lawful requests; retain records as required |

**Lawful bases (pilot framing):** employment-related legitimate interest / contract with the employer; **consent** for biometric processing; compliance with legal obligations where applicable.

---

## 4. How biometric data is handled

1. A manager/owner (or authorized flow) enrolls an employee’s face after consent.  
2. The system converts face samples into **embedding vectors** stored in the database.  
3. At clock-in, new captures are compared to that employee’s enrolled embeddings.  
4. Liveness checks reduce use of static photos.  
5. Matching is scoped to the logged-in employee / business — not used to identify random people in public.  

Biometric templates are **not** encrypted like Apple Face ID Secure Enclave storage. They are protected by application security (HTTPS, authentication, access control, tenant isolation). Details: [../SECURITY-PLAN.md](../SECURITY-PLAN.md).

---

## 5. Sharing and disclosure

We may share data only with:

| Recipient | Why |
|-----------|-----|
| Your employer (owner/managers) | Workforce, attendance, and payroll administration for your business |
| Platform administrators | Business registration review and platform operations |
| Hosting / infrastructure providers | Running servers and databases under contractual controls |
| Thesis supervisors / evaluators | Aggregated or minimized study results where appropriate |
| Authorities | When required by law |

We do **not** share face embeddings with other businesses on the platform.

---

## 6. Storage, security, and retention

### Security measures (summary)

- HTTPS in staging/production  
- JWT authentication and role-based access  
- Per-business data isolation  
- Password hashing (bcrypt)  
- Secure token storage on mobile  
- Server-side face/liveness validation for attendance  

### Retention (pilot defaults — adjust if needed)

| Data | Retention |
|------|-----------|
| Account & employment records | Duration of employment on the platform + pilot wind-down period |
| Attendance & payslips | Duration of pilot / employer need for pay disputes (recommended: at least through final payroll of the pilot) |
| Face embeddings | While the employee is active and enrolled; delete on face clear / offboarding |
| Raw face images | Transient processing only; not long-term storage by design |
| Registration uploads | Until review complete + pilot record-keeping need |
| Security logs | Limited period needed for operations (e.g. 30–90 days) unless investigating an incident |

At pilot end, `[ORGANIZATION NAME]` will delete or anonymize personal data that is no longer needed, unless retention is required for academic documentation with minimized identifiers, or by law.

---

## 7. Your rights

Subject to the Data Privacy Act and practical limits of the pilot, you may request to:

- **Access** personal data we hold about you  
- **Correct** inaccurate data  
- **Withdraw biometric consent** (may prevent face-based clock-in; employer may provide an alternative process for the pilot)  
- **Request deletion** of biometric templates when leaving employment or withdrawing consent  
- **Complain** to the National Privacy Commission (NPC) if you believe your privacy rights were violated  

How to exercise rights: email `[CONTACT EMAIL]` and copy your employer’s owner/manager for employment records they control.

---

## 8. Children

Aroll+ is intended for adult employees and business users. It is not directed at children under 18.

---

## 9. International / cross-border processing

If hosting is outside the Philippines, personal data may be processed in that region under this Policy and applicable safeguards. Prefer Philippine or clearly disclosed hosting for the pilot when possible.

---

## 10. Changes to this Policy

We may update this Policy during the pilot. Material changes will be communicated via the app, admin web notice, or email where practical. The **Effective date** above will be updated.

---

## 11. Contact

Privacy questions or requests: `[CONTACT EMAIL]`  
Operator: `[ORGANIZATION NAME]`

---

## Acknowledgement (optional)

I have read the Aroll+ Privacy Policy and understand how my personal data is used in the pilot.

| Field | Value |
|-------|--------|
| Full name | |
| Date | |
| Signature / digital acknowledgement | |
