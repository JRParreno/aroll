from fastapi import HTTPException


MAX_PROFILE_IMAGE_BYTES = 2_500_000


def validate_profile_image_data(image_data: str) -> str:
    image_data = image_data.strip()
    if not image_data.startswith("data:image/") or "," not in image_data:
        raise HTTPException(400, "Invalid image data")
    if len(image_data) > MAX_PROFILE_IMAGE_BYTES:
        raise HTTPException(400, "Image is too large")
    return image_data
