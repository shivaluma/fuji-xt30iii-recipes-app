import { ImageResponse } from "next/og";

export const size = { width: 64, height: 64 };
export const contentType = "image/png";

/** FilmLab mark: white "F" on an ink tile (replaces the Next.js default favicon). */
export default function Icon() {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", background: "#0c0c0c", color: "#fff", borderRadius: 22, fontSize: 44, letterSpacing: -2, paddingBottom: 3 }}>
        F
      </div>
    ),
    size,
  );
}
