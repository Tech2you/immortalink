export class TranscriptionError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}

// A provider timeout has an ambiguous billing outcome. Do not automatically
// create a second paid request for the same audio; support can review failed jobs.
export async function runTranscriptionJob({ claim, consume, transcribe, finish, release }: {
  claim: () => Promise<{ claimed: boolean; status: string; transcript?: string }>;
  consume: () => Promise<string | null>;
  transcribe: () => Promise<string>;
  finish: (status: "succeeded" | "failed", transcript?: string) => Promise<void>;
  release: () => Promise<void>;
}): Promise<string> {
  const job = await claim();
  if (!job.claimed) {
    if (job.status === "succeeded") return job.transcript || "";
    if (job.status === "processing") throw new TranscriptionError(409, "TRANSCRIPTION_PROCESSING", "This recording is already being transcribed. Please check again shortly.");
    throw new TranscriptionError(503, "TRANSCRIPTION_REVIEW_REQUIRED", "The recording is saved, but transcription could not be completed. Contact support before retrying.");
  }
  try {
    const quotaError = await consume();
    if (quotaError) throw new TranscriptionError(429, "TRANSCRIPTION_QUOTA", quotaError);
  } catch (error) {
    await release();
    throw error;
  }
  try {
    const transcript = await transcribe();
    await finish("succeeded", transcript);
    return transcript;
  } catch (error) {
    await finish("failed");
    throw error;
  }
}
