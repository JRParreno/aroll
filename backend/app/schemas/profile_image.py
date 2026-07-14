from pydantic import BaseModel


class ProfileImageRequest(BaseModel):
    image_data: str


class OwnerProfileImageResponse(BaseModel):
    owner_profile_image_url: str | None = None


class EmployeeProfileImageResponse(BaseModel):
    profile_image_url: str | None = None
