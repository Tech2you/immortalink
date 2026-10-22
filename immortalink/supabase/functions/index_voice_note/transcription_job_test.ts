import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { runTranscriptionJob, TranscriptionError } from "./transcription_job.ts";
import { validateAudio } from "./audio_validation.ts";

function wav(seconds: number): Uint8Array {
  const data = new Uint8Array(44 + seconds * 16000);
  const view = new DataView(data.buffer);
  const text = (offset: number, value: string) => data.set(new TextEncoder().encode(value), offset);
  text(0,"RIFF"); view.setUint32(4,data.length-8,true); text(8,"WAVEfmt ");
  view.setUint32(16,16,true); view.setUint16(20,1,true); view.setUint16(22,1,true);
  view.setUint32(24,8000,true); view.setUint32(28,16000,true); view.setUint16(32,2,true);
  view.setUint16(34,16,true); text(36,"data"); view.setUint32(40,data.length-44,true);
  return data;
}
Deno.test("duration comes from the audio file; invalid and overlong audio is refused", async () => {
  const result=await validateAudio(wav(2));
  assertEquals(result.seconds,2);
  assertEquals(result.hash.length,64);
  await assertRejects(()=>validateAudio(wav(121)),Error,"AUDIO_DURATION_INVALID");
  await assertRejects(()=>validateAudio(new Uint8Array()),Error,"AUDIO_SIZE_INVALID");
  await assertRejects(()=>validateAudio(new TextEncoder().encode("not audio")));
});
Deno.test("only a new job consumes quota and calls the provider", async () => {
  let calls=0; let consumed=0; let status="processing"; let transcript=""; let exists=false;
  const options={
    claim:async()=>{const claimed=!exists;exists=true;return {claimed,status,transcript};},
    consume:async()=>{consumed++;return null;},
    transcribe:async()=>{calls++;return "Saved voice";},
    finish:async(s: "succeeded"|"failed",t?:string)=>{status=s;transcript=t||"";},
    release:async()=>{exists=false;},
  };
  assertEquals(await runTranscriptionJob(options),"Saved voice");
  assertEquals(await runTranscriptionJob(options),"Saved voice");
  assertEquals(calls,1);assertEquals(consumed,1);
});
Deno.test("in-flight or ambiguous failed requests never start another paid call",async()=>{
  for (const status of ["processing","failed"]) {
    let calls=0;
    await assertRejects(()=>runTranscriptionJob({claim:async()=>({claimed:false,status}),
      consume:async()=>{calls++;return null;},transcribe:async()=>{calls++;return "";},
      finish:async()=>{},release:async()=>{}}),TranscriptionError);
    assertEquals(calls,0);
  }
});
Deno.test("quota failure releases unstarted work; provider failure is retained",async()=>{
  let released=0;let finished="";let calls=0;
  const options={claim:async()=>({claimed:true,status:"processing"}),consume:async()=>"Quota exhausted",
    transcribe:async()=>{calls++;throw new Error("timeout");},
    finish:async(status:"succeeded"|"failed")=>{finished=status;},release:async()=>{released++;}};
  await assertRejects(()=>runTranscriptionJob(options),TranscriptionError);
  assertEquals(released,1);assertEquals(calls,0);
  await assertRejects(()=>runTranscriptionJob({...options,consume:async()=>null}),Error,"timeout");
  assertEquals(released,1);assertEquals(calls,1);assertEquals(finished,"failed");
});
