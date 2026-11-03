import "server-only";
import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { UPLOAD_DIR } from "@/lib/server/db";

/** Shared 1200×630 share card: full-bleed photo, ©FilmLab pill, optional dark tag, title bottom-left. */
export const OG_SIZE = { width: 1200, height: 630 };

const dataUri = (buf: Buffer, ext: string) => `data:image/${ext === "png" ? "png" : "jpeg"};base64,${buf.toString("base64")}`;

/** The Mt Fuji hero as JPEG (the card renderer can't decode WebP). */
export async function defaultPhoto() {
  return dataUri(await readFile(path.join(process.cwd(), "public/og/mt-fuji.jpg")), "jpg");
}

/** An uploaded cover, when it's a JPEG/PNG; WebP covers fall back to the default photo. */
export async function coverPhoto(file: string | null | undefined) {
  if (!file || !/^[0-9a-f-]{36}\.(jpg|png)$/.test(file)) return defaultPhoto();
  try {
    return dataUri(await readFile(path.join(/*turbopackIgnore: true*/ UPLOAD_DIR, file)), file.split(".").pop()!);
  } catch {
    return defaultPhoto();
  }
}

export function ogCard({ photo, eyebrow, title, tag }: { photo: string; eyebrow?: string; title: string; tag?: string | null }) {
  const big = title.length <= 26;
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", position: "relative", background: "#0c0c0c" }}>
        {/* eslint-disable-next-line @next/next/no-img-element, jsx-a11y/alt-text */}
        <img src={photo} width={1200} height={630} style={{ position: "absolute", top: 0, left: 0, width: 1200, height: 630, objectFit: "cover" }} />
        <div style={{ position: "absolute", top: 0, left: 0, width: 1200, height: 630, display: "flex", background: "linear-gradient(180deg, rgba(0,0,0,0) 30%, rgba(0,0,0,.75) 100%)" }} />
        <div style={{ position: "absolute", top: 0, left: 0, width: 1200, height: 630, display: "flex", flexDirection: "column", justifyContent: "space-between", padding: 56 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ display: "flex", background: "rgba(255,255,255,.92)", color: "#0c0c0c", borderRadius: 999, padding: "12px 24px", fontSize: 28 }}>©FilmLab</div>
            {tag ? <div style={{ display: "flex", background: "rgba(0,0,0,.72)", color: "#fff", borderRadius: 999, padding: "12px 24px", fontSize: 26 }}>{tag}</div> : null}
          </div>
          <div style={{ display: "flex", flexDirection: "column", color: "#fff", maxWidth: 1000 }}>
            {eyebrow ? <div style={{ display: "flex", fontSize: 24, letterSpacing: 3, textTransform: "uppercase", opacity: 0.85 }}>{eyebrow}</div> : null}
            <div style={{ display: "flex", marginTop: 16, fontSize: big ? 96 : 72, lineHeight: 1, letterSpacing: big ? -4 : -3 }}>{title}</div>
          </div>
        </div>
      </div>
    ),
    OG_SIZE,
  );
}
