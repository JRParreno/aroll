/// Default map center (Manila) when no business location is saved yet.
const double kDefaultBusinessLatitude = 14.5995;
const double kDefaultBusinessLongitude = 120.9842;

const int kMinGeofenceRadiusM = 5;
const int kMaxGeofenceRadiusM = 200;
const int kDefaultGeofenceRadiusM = 75;

/// Radii at or below this use "small fence" GPS handling (more samples,
/// longer wait, uncertainty-aware validation). Outdoor GPS often drifts
/// 8–15 m, so tight fences need special care.
const int kSmallGeofenceRadiusM = 20;

bool isSmallGeofenceRadius(num radiusM) => radiusM <= kSmallGeofenceRadiusM;

const String kSmallGeofenceOwnerTip =
    'Warning: radii under 20 m can be unreliable because phone GPS often '
    'drifts 8–15 m. Prefer outdoor placement near the pin. '
    'You can still use a small radius if needed; 25–50 m is more reliable.';
