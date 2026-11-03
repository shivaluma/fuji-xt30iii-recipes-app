import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

/** FilmLab mark: white "F" on an ink tile (replaces the Next.js default favicon). */
export default function Icon() {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", background: "#0c0c0c", color: "#fff", borderRadius: 0, fontSize: 120, letterSpacing: -4, paddingBottom: 9 }}>
        F
      </div>
    ),
    size,
  );
}
