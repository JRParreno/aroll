import { readdirSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const vitestFiles = new Set([
  "ownerFirstLoginPath.test.ts",
  "payslipReceipt.test.ts",
  "shiftHistoryPayBreakdown.test.ts",
]);

function collectNodeTests(directory, files) {
  for (const entry of readdirSync(directory)) {
    const fullPath = path.join(directory, entry);
    if (statSync(fullPath).isDirectory()) {
      collectNodeTests(fullPath, files);
      continue;
    }
    if (entry.endsWith(".test.ts") && !vitestFiles.has(entry)) {
      files.push(fullPath);
    }
  }
}

const nodeTests = [];
collectNodeTests(path.join(root, "src"), nodeTests);
nodeTests.sort();

const nodeResult = spawnSync(process.execPath, ["--test", ...nodeTests], {
  cwd: root,
  stdio: "inherit",
});
if (nodeResult.status !== 0) {
  process.exit(nodeResult.status ?? 1);
}

const vitestResult = spawnSync(
  process.execPath,
  [path.join(root, "node_modules", "vitest", "vitest.mjs"), "run"],
  { cwd: root, stdio: "inherit" }
);
process.exit(vitestResult.status ?? 1);
