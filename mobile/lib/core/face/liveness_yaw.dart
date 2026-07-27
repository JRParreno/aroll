/// Helpers for Strong head-turn liveness using ML Kit yaw.
///
/// Front camera preview is mirrored. Map UI arrows so "LEFT" matches the
/// server `turn_left` / `turn_right` direction, not the mirrored preview.
library;

const double centerYawMaxDeg = 12;
const double turnYawMinDeg = 18;

/// ML Kit `headEulerAngleY`: positive = face turned toward the subject's left
/// (viewer's right on a mirrored front camera). For server `turn_left`, the
/// employee turns their head left → typically negative yaw on many devices;
/// we accept magnitude in the instructed direction with a sign convention
/// aligned to the admin-web observe path (server uses YuNet yaw separately).
bool isCenteredYaw(double? yaw) {
  if (yaw == null) return false;
  return yaw.abs() <= centerYawMaxDeg;
}

bool isTurnYaw(double? yaw, {required bool turnLeft}) {
  if (yaw == null) return false;
  // Front-camera: turning LEFT often produces positive headEulerAngleY in ML Kit
  // when the preview is mirrored; treat |yaw| past threshold in the expected sign.
  if (turnLeft) {
    return yaw >= turnYawMinDeg;
  }
  return yaw <= -turnYawMinDeg;
}

String directionLabel(String direction) =>
    direction == 'turn_left' ? 'LEFT' : 'RIGHT';
