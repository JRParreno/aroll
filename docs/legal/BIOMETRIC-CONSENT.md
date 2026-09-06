# Aroll+ Biometric Data Consent Form

**Document type:** Informed consent for facial biometric processing  
**Related:** [PRIVACY-POLICY.md](PRIVACY-POLICY.md) · [TERMS-AND-CONDITIONS.md](TERMS-AND-CONDITIONS.md) · [../SECURITY-PLAN.md](../SECURITY-PLAN.md)

**Effective / form version date:** `[EFFECTIVE DATE]`  
**Platform operator:** `[ORGANIZATION NAME]` (`[CONTACT EMAIL]`)

> Complete this form **before** face enrollment. Keep a copy with the employer. For in-app consent, record name, employee id, timestamp, and policy version.

---

## A. Parties

| Field | Information |
|-------|-------------|
| Business / employer name | `[BUSINESS NAME]` |
| Employee full name | |
| Employee email / code | |
| Position | |
| Date of consent | |

---

## B. Plain-language summary

Your employer uses **Aroll+** to record attendance. To reduce time theft and confirm it is really you clocking in, Aroll+ may use your **face**:

1. During **enrollment**, the system captures several face samples and converts them into a **numeric template** (embedding).  
2. During **clock-in / clock-out**, the app captures your face, checks that you are a live person (liveness), checks you are near the workplace (GPS geofence), and compares your face template to the enrolled one.  
3. Raw photos are processed to create templates and are **not meant to be stored long-term** as a photo album. Templates are stored in the Aroll+ database for matching.  
4. This is **not** the same as Apple Face ID on-device encryption. Templates are protected by the system’s normal security (login, access control, HTTPS).

You can read full details in the [Privacy Policy](PRIVACY-POLICY.md).

---

## C. Purpose of processing

I understand that my facial biometric data will be used **only** for:

- Enrolling my face for workplace attendance verification  
- Verifying my identity when clocking in and out  
- Supporting related attendance records used by my employer for timekeeping and payroll  

It will **not** be used for marketing, sold to third parties, or shared with other businesses on Aroll+.

---

## D. Data processed

- Face images during enrollment and attendance capture (transient processing)  
- Face embedding(s) stored for matching  
- Liveness and match results linked to attendance events  
- Location coordinates at clock-in/out for geofence checks  

---

## E. Voluntary consent and employment note

- Face enrollment for this pilot is based on my **consent**.  
- If I refuse or later withdraw consent, I understand I may be unable to use face-based clock-in. My employer should provide an alternative attendance process for the pilot where required.  
- Refusing biometric consent should not be used to unlawfully discriminate; employment consequences are governed by my employer and applicable labor law—not by this form alone.

---

## F. Storage, access, and retention

- Templates are stored in Aroll+ under my employer’s business account, accessible to authorized owner/manager users and technical operators as needed to run the system.  
- Templates should be deleted when my face registration is cleared, when I leave employment, or when I withdraw consent and deletion is requested (subject to any short retention needed to complete an open attendance/pay period).  
- Pilot retention follows the Privacy Policy and `[ORGANIZATION NAME]` wind-down process (target end: `[PILOT END DATE]` unless extended).

---

## G. Rights

I may request access, correction, withdrawal of this consent, or deletion of my biometric templates by contacting my employer and/or `[CONTACT EMAIL]`, as described in the Privacy Policy. I may also complain to the National Privacy Commission.

---

## H. Risks (informed)

I understand that:

- Face recognition may occasionally fail (lighting, angle, lookalikes) and may require retry or re-enrollment.  
- Strong liveness reduces photo spoofing but may not stop all advanced attacks (e.g. certain videos).  
- Unauthorized access to systems is a residual risk mitigated by the Security Plan, not zero risk.

---

## I. Consent declaration

By signing below, I confirm that:

1. I have read this form and the Aroll+ Privacy Policy (or had them explained to me in a language I understand).  
2. I voluntarily consent to the collection and processing of my facial biometric data for the purposes in Section C.  
3. I understand I may withdraw consent as described in Section E and G.

### Employee

| Field | Value |
|-------|--------|
| Printed name | |
| Signature | |
| Date | |

### Employer witness (owner / manager)

| Field | Value |
|-------|--------|
| Printed name | |
| Position | |
| Signature | |
| Date | |

---

## J. Withdrawal of consent (optional later use)

I withdraw my biometric consent for Aroll+ face processing. I request deletion of my face embeddings subject to the Privacy Policy.

| Field | Value |
|-------|--------|
| Employee name | |
| Date of withdrawal | |
| Signature | |
| Employer acknowledgement | |
| Embeddings cleared on (date) | |
| Cleared by | |

---

## Digital consent log (if collected in-app)

| Field | Value |
|-------|--------|
| `user_id` / `employee_id` | |
| Policy / consent version | e.g. `biometric-consent-2026-09-06` |
| Accepted at (UTC) | |
| Client (mobile / web) | |
| IP or device note (optional) | |
