import { describe, expect, test } from "bun:test";
import { mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
// Export these from main.ts as part of this task:
import { safeExistingPath, assertWritableTarget } from "../src/main";

describe("workspace sandbox (security invariant — spec §1)", () => {
  const ws = mkdtempSync(join(tmpdir(), "pi-ws-"));
  const outside = mkdtempSync(join(tmpdir(), "pi-outside-"));

  test("read outside workspace is denied", async () => {
    writeFileSync(join(outside, "secret.txt"), "nope");
    await expect(safeExistingPath(ws, join(outside, "secret.txt"))).rejects.toThrow(
      /escapes workspace/i,
    );
  });

  test("write outside workspace is denied", async () => {
    await expect(assertWritableTarget(ws, join(outside, "evil.txt"))).rejects.toThrow(
      /escapes workspace/i,
    );
  });

  test("symlink escape is denied", async () => {
    const link = join(ws, "link-out");
    symlinkSync(outside, link);
    await expect(assertWritableTarget(ws, join(link, "evil.txt"))).rejects.toThrow();
  });

  test("path inside workspace is allowed", async () => {
    writeFileSync(join(ws, "ok.txt"), "fine");
    const result = await safeExistingPath(ws, join(ws, "ok.txt"));
    expect(result).toContain(ws);
  });
});
