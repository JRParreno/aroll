import qrcode from "qrcode";

type QrModules = {
  size: number;
  get: (row: number, column: number) => number | boolean;
};

type QrSymbol = {
  modules: QrModules;
  segments: Array<{ data: Uint8Array }>;
};

type QrEncoder = {
  create: (value: string) => QrSymbol;
};

function encoder(): QrEncoder {
  const candidate = qrcode as QrEncoder & { default?: QrEncoder };
  if (typeof candidate.create === "function") return candidate;
  if (candidate.default && typeof candidate.default.create === "function") return candidate.default;
  throw new Error("QR encoder is unavailable");
}

export function apkQrPayload(symbol: QrSymbol): string {
  return new TextDecoder().decode(symbol.segments[0]?.data ?? new Uint8Array());
}

/** Square SVG QR code with a four-module quiet zone. Dark modules sit on white. */
export function apkQrSvg(value: string, margin = 4): { svg: string; payload: string } {
  const symbol = encoder().create(value);
  const size = symbol.modules.size;
  const dimension = size + margin * 2;
  const cells: string[] = [];
  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      if (symbol.modules.get(row, column)) {
        cells.push(`<rect x="${column + margin}" y="${row + margin}" width="1" height="1"/>`);
      }
    }
  }
  const svg = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${dimension} ${dimension}" width="${dimension}" height="${dimension}" shape-rendering="crispEdges" aria-hidden="true">`,
    `<rect width="${dimension}" height="${dimension}" fill="#FFFFFF"/>`,
    `<g fill="#172554">${cells.join("")}</g>`,
    "</svg>",
  ].join("");
  return { svg, payload: apkQrPayload(symbol) };
}
