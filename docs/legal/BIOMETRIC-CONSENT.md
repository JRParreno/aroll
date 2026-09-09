# Aroll+ Biometric / Face Information and Consent

Last updated: 8 September 2026

Please read this information before enrolling your face in Aroll+.

This notice supports informed use of face-based attendance in an academic prototype. It is not a claim that Aroll+ records a government-registered biometric template or a server-side legal consent ledger.

## 1. What you are being asked

Live employees must enroll their face before using camera-based Time In and Time Out. Enrollment lets Aroll+ confirm that the person recording attendance is the signed-in employee.

## 2. What is collected

During enrollment, the app uses the camera to capture several short face images. Those images are processed into a numeric **face embedding** (a list of numbers that describes your face for matching).

During live Time In / Time Out, the app may capture another face image and send it with workplace coordinates so the server can match it against your enrolled embeddings.

Aroll+ does not keep enrollment photos as a long-term photo gallery. Matching uses embeddings and the existing face-recognition pipeline. Demo accounts do not enroll a live face or open the camera for attendance.

## 3. Why this is used

Face matching is used only to:

- Complete your employee face setup
- Verify it is you during live Time In / Time Out

It is not used to search other people’s photos or to enroll someone else’s face under your account.

## 4. Location during attendance

Live attendance also checks that you are within the business geofence using device location. That is separate from face enrollment, and it is explained again before location permission is requested.

## 5. What happens if you do not agree

If you do not agree, do not continue enrollment. The camera will not be used to collect enrollment samples until you continue from this screen.

Without enrollment, live face-based Time In / Time Out will not be available.

## 6. Storage and access

Embeddings are stored with your employee record in the Aroll+ database for this deployment. Business owners and administrators who already can manage attendance may see related attendance results, not a public face database.

## 7. Confirmation

Tapping **I understand and continue** means you have read this information and agree to enroll your face for Aroll+ attendance on this device.

That confirmation is required on this screen before the camera starts. Aroll+ does not currently save a separate biometric-consent row on the server.
