# Aroll+ Privacy Policy

Last updated: 8 September 2026

This Privacy Policy describes how the Aroll+ thesis prototype handles personal information. It is intended to support transparency under the Philippines Data Privacy Act of 2012 (Republic Act No. 10173) for an academic system.

This Policy does not claim that Aroll+ is a commercially certified compliance product.

## 1. Who is responsible

The student developers operating a given Aroll+ deployment act as the system administrators for that deployment. Your employer (the registered business owner) decides which employees are enrolled and which workplace data are entered.

## 2. Information Aroll+ may process

Depending on your role, Aroll+ may process:

- Account details: name, email or username, role, business name, and business code
- Employee profile details: position, phone number, employment type, and optional profile photo
- Business details: address, workplace coordinates, geofence radius, schedules, and documents submitted during registration
- Attendance records: Time In, Time Out, status, and related location coordinates used for geofence checks
- Face-related data: numeric face embeddings created from enrollment and attendance captures
- Leave and payroll records derived from attendance and owner configuration
- In-app notifications about attendance, schedule, leave, or payroll events
- Device permission status for camera, location, and notifications (held on the device)

Demo / research accounts may display simulated attendance, payroll, biometric, and workplace-location data. Simulated data is for demonstration and is not a real employee performance evaluation.

## 3. Why Aroll+ uses this information

- To create and authenticate accounts
- To verify identity during live face-based Time In / Time Out
- To confirm that live attendance occurs near the configured workplace
- To calculate attendance status and payroll figures from recorded time
- To let owners review registrations, employees, schedules, and requests
- To show in-app notifications

## 4. Camera, location, and notifications

Aroll+ requests device permissions only when a feature needs them:

- **Camera** — face enrollment and live face-based attendance
- **Location / GPS** — live attendance geofence checks
- **Notifications** — optional system permission so the device may present attendance and other in-app alerts

Demo attendance does not request camera or phone GPS.

## 5. Face / biometric-related data

Aroll+ uses face images to create embeddings for matching. Details are in the Biometric Consent document.

Live attendance compares a fresh capture against the logged-in employee’s enrolled embeddings. The system is not designed as a public face-search service.

## 6. Storage and sharing

Data is stored in the Aroll+ backend database used by your deployment. Face embeddings are stored for matching. Enrollment images are processed and are not retained as a long-term photo album.

Information may be visible to:

- The employee, for their own records
- The business owner / authorized workplace account
- Platform administrators, for business registration review
- Academic evaluators, when a research or demo protocol requires it

Aroll+ does not sell personal information.

## 7. Retention

Data is kept for as long as the academic deployment and the business account remain active, or until records are deleted by an authorized administrator as part of project close-out.

## 8. Your choices

You may:

- Read these documents from the login and in-app legal pages
- Decline camera, location, or notification permissions (some live features will not work)
- Decline biometric consent, in which case live face enrollment will not proceed

Aroll+ does **not** currently store a server-side “I accepted the Privacy Policy” record at login. Access to the full Policy is provided so you can read it before and during use.

## 9. Security

Access uses authenticated sessions. You should still treat this as a prototype: do not upload unnecessary sensitive documents, and do not use production secrets in demo environments.

## 10. Contact

Privacy questions may be directed to your course instructor or the Aroll+ project team for this deployment.
