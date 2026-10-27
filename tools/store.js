/* ---------- Shared Store (here.now Site Data) — adapted from the Kanban board's tools/store.js ----------
   Every cat and every log entry is one record in the Site's public "items" collection:
     {item_id, payload, changed_at, deleted, device}
   Merge rule: per item, the newest updatedAt wins. Deletes are tombstones (deleted:true) so they sync too.
   A localStorage cache makes the app load instantly and keeps working offline; edits queue and push later.
   No credentials are used here: the page talks only to its own site's /.herenow/data/ endpoint. */
const Store=(function(){
  const KEY='jl-cat-health-shared-v1', API='/*DATA_API*/', POLL_MS=4000;
  const subs=new Set(), statusSubs=new Set();
  const blank=()=>({state:null,rid:{},seen:{},dirty:{},tombs:{},synced:false});
  let c=blank();
  try{const raw=localStorage.getItem(KEY);if(raw)c=Object.assign(blank(),JSON.parse(raw));}catch(e){console.warn('Could not read cache',e);}
  const clone=o=>JSON.parse(JSON.stringify(o));
  function persist(){try{localStorage.setItem(KEY,JSON.stringify(c));return true;}catch(e){return false;}}
  let status='busy',statusLabel='Connecting…',lastOk=0,failing=false,inflight=false,timer=null,again=false,stopped=true,lastErr='';
  function setStatus(s,l){status=s;statusLabel=l;statusSubs.forEach(f=>f(s,l));}
  function pendingCount(){return Object.keys(c.dirty).length;}
  function refreshStatus(){
    if(!navigator.onLine)return setStatus('off',pendingCount()?`Offline · ${pendingCount()} to sync`:'Offline · saved here');
    if(failing)return setStatus('err',pendingCount()?`Can’t sync · ${pendingCount()} waiting`:'Can’t reach server');
    if(inflight||pendingCount())return setStatus('busy','Syncing…');
    setStatus('ok','Synced');
  }
  function load(){return c.state?clone(c.state):{items:[]};}
  function J(x){return JSON.stringify(x,(k,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.keys(v).sort().reduce((o,kk)=>(o[kk]=v[kk],o),{}):v);}
  function save(data){
    const prev=c.state?c.state.items:[];const pm=new Map(prev.map(x=>[x.id,x]));const now=Date.now();const ids=new Set();
    for(const x of data.items){ids.add(x.id);const p=pm.get(x.id);
      if(!p||J(p)!==J(x)){if(p&&!(x.updatedAt>p.updatedAt))x.updatedAt=Math.max(now,(p.updatedAt||0)+1);if(!x.updatedAt)x.updatedAt=now;c.dirty[x.id]=1;delete c.tombs[x.id];}}
    for(const p of prev)if(!ids.has(p.id)){c.tombs[p.id]=Math.max(now,(p.updatedAt||0)+1);c.dirty[p.id]=1;}
    c.state=clone(data);const ok=persist();refreshStatus();kick(250);return ok;
  }
  function subscribe(fn){subs.add(fn);return()=>subs.delete(fn);}
  function notify(){const d=clone(c.state);subs.forEach(f=>f(d));}
  async function req(url,opt){const r=await fetch(url,Object.assign({cache:'no-store'},opt||{}));let j=null;try{j=await r.json();}catch(_){}
    if(!r.ok){const e=new Error((j&&(j.message||j.error))||('HTTP '+r.status));e.status=r.status;e.retry=j&&j.retry_after;throw e;}return j;}
  async function pullAll(){const out=[];let cur=null,guard=0;
    do{const j=await req(API+'?limit=100'+(cur?'&cursor='+encodeURIComponent(cur):''));out.push(...(j.records||[]));cur=j.nextCursor;}while(cur&&++guard<300);
    return out;}
  function merge(records){
    const best=new Map();
    for(const r of records){const d=r.data||{};if(!d.item_id)continue;const b=best.get(d.item_id);
      if(!b||d.changed_at>b.data.changed_at||(d.changed_at===b.data.changed_at&&r.updatedAt>b.updatedAt))best.set(d.item_id,r);}
    if(!c.state)c.state={items:[]};
    const items=new Map(c.state.items.map(x=>[x.id,x]));let changed=false;
    for(const [id,r] of best){const d=r.data;c.rid[id]=r.id;c.seen[id]=d.changed_at;
      const loc=items.get(id),localAt=loc?loc.updatedAt:(c.tombs[id]||-1);
      if(d.changed_at>localAt){delete c.dirty[id];
        if(d.deleted){if(loc){items.delete(id);changed=true;}c.tombs[id]=d.changed_at;}
        else if(d.payload&&d.payload.id===id){items.set(id,Object.assign({},d.payload,{updatedAt:d.changed_at}));delete c.tombs[id];changed=true;}}
      else if(d.changed_at<localAt)c.dirty[id]=1;
    }
    // records the owner removed from the server (e.g. cleanup) disappear here too, unless edited locally
    for(const id of Object.keys(c.rid))if(!best.has(id)){delete c.rid[id];delete c.seen[id];delete c.tombs[id];if(!c.dirty[id]&&items.has(id)){items.delete(id);changed=true;}}
    for(const id of items.keys())if(!best.has(id))c.dirty[id]=1; // never reached the server yet
    if(changed)c.state.items=[...items.values()];
    return {changed,empty:records.length===0};
  }
  async function push(id){
    const it=c.state.items.find(x=>x.id===id);let body;
    if(it)body={item_id:id,payload:it,changed_at:it.updatedAt,deleted:false};
    else if(c.tombs[id])body={item_id:id,payload:{},changed_at:c.tombs[id],deleted:true};
    else{delete c.dirty[id];return;}
    if(c.seen[id]!=null&&c.seen[id]>=body.changed_at&&c.rid[id]){delete c.dirty[id];return;}
    body.device=(typeof me==='string'&&me)||'';
    if(JSON.stringify(body).length>15000)throw Object.assign(new Error('Entry is too big to sync (16 KB limit)'),{status:413});
    let r=null;
    if(c.rid[id]){try{r=await req(API+'/'+encodeURIComponent(c.rid[id]),{method:'PATCH',headers:{'content-type':'application/json'},body:JSON.stringify(body)});}
      catch(e){if(e.status!==404)throw e;delete c.rid[id];}}
    if(!r)r=await req(API,{method:'POST',headers:{'content-type':'application/json','Idempotency-Key':id+':'+body.changed_at},body:JSON.stringify(body)});
    if(r&&r.record){c.rid[id]=r.record.id;c.seen[id]=body.changed_at;}
    const nowAt=(c.state.items.find(x=>x.id===id)||{}).updatedAt||c.tombs[id];
    if(nowAt===body.changed_at)delete c.dirty[id];
  }
  async function cycle(){
    if(inflight){again=true;return;}inflight=true;refreshStatus();let wait=POLL_MS;
    try{
      if(navigator.onLine===false)throw Object.assign(new Error('offline'),{offline:true});
      const recs=await pullAll();const {changed}=merge(recs);
      c.synced=true;persist();if(changed)notify();
      for(const id of Object.keys(c.dirty)){await push(id);}
      persist();failing=false;lastOk=Date.now();lastErr='';
    }catch(e){if(!e.offline){failing=true;lastErr=e.message;console.warn('Sync problem:',e.message);}
      if(e.status===429)wait=Math.max(15000,(e.retry||15)*1000);else wait=8000;persist();}
    finally{inflight=false;refreshStatus();if(again){again=false;wait=200;}schedule(wait);}
  }
  function schedule(ms){clearTimeout(timer);if(stopped)return;if(document.hidden)return;timer=setTimeout(cycle,ms);}
  function kick(ms){if(stopped)return;if(inflight){again=true;return;}schedule(ms||0);}
  function start(){stopped=false;refreshStatus();kick(0);}
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)kick(0);else clearTimeout(timer);});
  addEventListener('online',()=>kick(0));addEventListener('offline',refreshStatus);addEventListener('focus',()=>kick(0));
  addEventListener('storage',e=>{if(e.key===KEY&&e.newValue){try{const n=Object.assign(blank(),JSON.parse(e.newValue));if(n.state){const diff=J(n.state.items)!==J(c.state&&c.state.items);c=n;if(diff)notify();refreshStatus();}}catch(_){}}});
  return {load,save,subscribe,start,kind:'here.now Site Data',api:API,
    onStatus(fn){statusSubs.add(fn);fn(status,statusLabel);},
    syncNow(){kick(0);},
    debug(){return {dirty:Object.keys(c.dirty),records:Object.keys(c.rid).length,lastOk,status,lastErr,synced:c.synced};}};
})();
