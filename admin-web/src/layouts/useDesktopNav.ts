import { useEffect, useState } from "react";

const DESKTOP_NAV_QUERY = "(min-width: 1024px)";

export function useDesktopNav() {
  const [desktop, setDesktop] = useState(() =>
    typeof window !== "undefined"
      ? window.matchMedia(DESKTOP_NAV_QUERY).matches
      : true
  );

  useEffect(() => {
    const media = window.matchMedia(DESKTOP_NAV_QUERY);
    const update = () => setDesktop(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  return desktop;
}
