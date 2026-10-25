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
    'A small work area is harder for phone GPS, which often drifts '
    'by several meters. You can optionally register the workplace Wi-Fi as a '
    'backup when the work area is under 20 m. That only confirms the '
    'phone is connected to a network you saved. It is not a location measurement '
    'and does not replace the map boundary.';
