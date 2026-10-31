import { beforeEach, describe, expect, it, vi } from "vitest";

const invoke = vi.hoisted(() => vi.fn());
const check = vi.hoisted(() => vi.fn());
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("@tauri-apps/plugin-updater", () => ({ check }));

const load = async () => {
  vi.resetModules();
  return import("../updates");
};

describe("the notes of an update", () => {
  beforeEach(() => {
    invoke.mockReset();
    check.mockReset();
    check.mockResolvedValue({ version: "1.0.1", body: "From latest.json" });
  });

  it("follow the text on GitHub, so an edit there shows", async () => {
    invoke.mockResolvedValue("Edited on GitHub\n");
    const { checkForUpdate, updateState } = await load();
    await checkForUpdate();
    await vi.waitFor(() => expect(updateState().notes).toBe("Edited on GitHub"));
    expect(invoke).toHaveBeenCalledWith("release_notes", { version: "1.0.1" });
  });

  it("stay as latest.json has them when GitHub can't be read", async () => {
    invoke.mockRejectedValue({ code: "UpdateNetwork", message: "no network" });
    const { checkForUpdate, updateState } = await load();
    await checkForUpdate();
    await vi.waitFor(() => expect(invoke).toHaveBeenCalled());
    await Promise.resolve();
    expect(updateState().notes).toBe("From latest.json");
    expect(updateState().phase).toBe("found");
  });

  it("stay as latest.json has them when GitHub has no text", async () => {
    invoke.mockResolvedValue(null);
    const { checkForUpdate, updateState } = await load();
    await checkForUpdate();
    await vi.waitFor(() => expect(invoke).toHaveBeenCalled());
    await Promise.resolve();
    expect(updateState().notes).toBe("From latest.json");
  });
});
