import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const runtime = "nodejs";
export const alt = "Stepwell: when a vault loses money, underwriters pay first.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  const art = await readFile(join(process.cwd(), "app/section-src.jpg"));
  const src = `data:image/jpeg;base64,${art.toString("base64")}`;
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", position: "relative", background: "#f7f1e6" }}>
        {/* the drawing fills the right; its empty left half carries the words */}
        <img src={src} width={1200} height={631} style={{ position: "absolute", top: 0, left: 0 }} />
        <div style={{ display: "flex", flexDirection: "column", padding: "86px 0 0 72px", width: 500 }}>
          <div style={{ fontSize: 26, letterSpacing: 4, textTransform: "uppercase", color: "#6d6459" }}>Stepwell · on Arc</div>
          <div style={{ marginTop: 24, fontSize: 60, lineHeight: 1.06, fontWeight: 700, letterSpacing: -2, color: "#17150f" }}>
            When a vault loses money, underwriters pay first.
          </div>
          <div style={{ marginTop: 28, fontSize: 28, lineHeight: 1.35, color: "#423c33" }}>
            First-loss cover for Morpho vaults, paid from interest.
          </div>
        </div>
      </div>
    ),
    size,
  );
}
