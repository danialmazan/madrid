export type ShareOutcome = "shared" | "copied" | "aborted";

export interface ShareAdapters {
  share?: (data: ShareData) => Promise<void>;
  copy: (url: string) => Promise<void>;
}

export async function shareOrCopy(
  data: ShareData,
  adapters: ShareAdapters,
): Promise<ShareOutcome> {
  if (adapters.share) {
    try {
      await adapters.share(data);
      return "shared";
    } catch (error) {
      if (typeof error === "object" && error !== null && "name" in error && error.name === "AbortError") {
        return "aborted";
      }
    }
  }
  await adapters.copy(data.url ?? "");
  return "copied";
}
