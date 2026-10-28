import { BrowserEncryptedStorage } from "../../apps/mobile/src/host/browserStorage";
import { HostLifetime } from "../../apps/mobile/src/host/scope";
import { hostStores } from "../../apps/mobile/src/host/storage";
const scope = { endpoint: "https://host-test.invalid/v1", projectId: "browser-proof", accountId: "synthetic", appId: "browser-proof-kiqg2v6z-final" };
const input = { body: "Browser-private-synthetic-input ".repeat(170000) };
const command = { appId: scope.appId, operationId: "retained-original", versionId: "version-1", actionId: "create", input };
const host = (change = {}) => { const lifetime = new HostLifetime({ ...scope, ...change }); return hostStores(lifetime, new BrowserEncryptedStorage(lifetime)); };
function assert(value, code) { if (!value) throw new Error(code); }
const output = document.querySelector("pre");
let assertions = 0;
function verify(value, code) { assertions++; assert(value, code); }
function wire(id, run) { document.querySelector(id).addEventListener("click", async () => { assertions=0; output.textContent="Running"; try { await run(); output.textContent=JSON.stringify({status:"passed",assertions,layer:"real-browser-IndexedDB-WebCrypto",nativeDeviceProof:false},null,2); } catch(e) { output.textContent=JSON.stringify({status:"failed",assertions,code:e instanceof Error?e.message:"unknown"},null,2); } }); }
wire("#seed", async () => {
 const original=host(); await original.commands.save(command); original.lifetime.dispose();
 const recovered=host(); verify((await recovered.commands.read()).input.body===input.body,"large_recovery_failed");
 for(const change of [{accountId:"different"},{appId:"different"},{projectId:"different"},{endpoint:"https://another.invalid/v1"}]) { const other=host(change); verify(await other.commands.read()===null,"scope_isolation_failed"); other.lifetime.dispose(); }
 let conflict=false; try { await recovered.commands.save({...command,input:{body:"changed"}}); } catch { conflict=true; } verify(conflict,"changed_operation_not_rejected");
 let clearConflict=false; try { await recovered.commands.clear("other"); } catch { clearConflict=true; } verify(clearConflict,"wrong_clear_not_rejected");
 verify((await recovered.commands.read()).operationId===command.operationId,"wrong_clear_removed_original");
 const raceA=host({appId:scope.appId+"-race"}),raceB=host({appId:scope.appId+"-race"});
 const raceCommand={...command,appId:scope.appId+"-race",input:{body:"race"}};
 const result=await Promise.allSettled([raceA.commands.save(raceCommand),raceB.commands.save({...raceCommand,operationId:"second"})]);
 verify(result.filter(r=>r.status==="fulfilled").length===1,"competing_connections_overwrote_command");
 raceA.lifetime.dispose();raceB.lifetime.dispose();recovered.lifetime.dispose();
 const db=await new Promise((resolve,reject)=>{ const req=indexedDB.open("tinkerloom.private-host.v1",1);req.onsuccess=()=>resolve(req.result);req.onerror=reject; });
 const getAll=(store)=>new Promise((resolve,reject)=>{const req=db.transaction(store).objectStore(store).getAll();req.onsuccess=()=>resolve(req.result);req.onerror=reject;});
 const keys=await getAll("keys"); verify(keys.length>=2&&keys.every(key=>key.extractable===false),"encryption_keys_extractable");
 const rows=await getAll("ciphertext"); verify(rows.filter(row=>!row.removed).every(row=>row.data instanceof ArrayBuffer&&row.iv instanceof Uint8Array),"plaintext_row_found");
 const marker=new TextEncoder().encode("Browser-private-synthetic-input");
 verify(rows.filter(row=>!row.removed).every(row=>!new TextDecoder().decode(row.data).includes("Browser-private-synthetic-input")),"plaintext_marker_found"); db.close();
});
wire("#recover", async () => { const restored=host(); const value=await restored.commands.read(); verify(value.operationId===command.operationId,"reload_operation_lost");verify(value.versionId==="version-1"&&value.input.body===input.body,"reload_input_changed");restored.lifetime.dispose(); let fenced=false;try{await restored.commands.read();}catch{fenced=true;}verify(fenced,"closed_scope_read_allowed"); });

wire("#generic", async()=>{ const h=host(); const review={operationId:"publish",revision:7,hash:"reviewed",content:{title:"Original review"}}; const saving=h.storage.write("builder-command",review); review.content.title="Changed";await saving;const current=await h.storage.read("builder-command");verify(current.content.title==="Original review","builder_snapshot_changed");verify(await h.storage.compareAndSwap("builder-command",{operationId:"wrong"},null)===false,"wrong_cas_cleared_builder");verify(await h.storage.compareAndSwap("builder-command",current,{...current,confirmed:true})===true,"correct_cas_failed");verify(await h.storage.compareAndSwap("builder-command",current,null)===false,"stale_cas_deleted_new_state");verify((await h.storage.read("builder-command")).confirmed===true,"confirmed_builder_state_lost");h.lifetime.dispose(); });
