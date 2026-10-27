// Appointment feature test on a TEMPORARY test cat only. APP_URL=... node test/appts.js
// Afterwards run tools/clear-test-records.sh clear <snapshot> to remove the test records.
const {chromium}=require(__dirname+'/node_modules/playwright-core');
const cfg=require(__dirname+'/../secret-config.json');
const URL_=process.env.APP_URL||'http://localhost:8787/'+cfg.path_token+'/';
const res=[];const ok=(n,p,x='')=>{res.push(p);console.log((p?'PASS ':'FAIL ')+n+(x?' — '+x:''));};
(async()=>{
const b=await chromium.launch({executablePath:'/usr/bin/google-chrome',args:['--no-sandbox']});
const phone={viewport:{width:393,height:851},deviceScaleFactor:2,isMobile:true,hasTouch:true,timezoneId:'America/Chicago'};
const errs=[];
async function open(l,who){const ctx=await b.newContext(phone);const p=await ctx.newPage();p.on('pageerror',e=>errs.push(l+': '+e));p.on('dialog',d=>d.accept());
  await p.goto(URL_);await p.tap(`[data-who="${who}"]`);await synced(p);return p;}
const synced=p=>p.waitForFunction(()=>{const d=window.__cats.store.debug();return d.status==='ok'&&d.dirty.length===0&&d.synced;},null,{timeout:30000});
async function waitFor(p,fn,arg,ms=25000){const t0=Date.now();while(Date.now()-t0<ms){if(await p.evaluate(fn,arg))return Date.now()-t0;await p.waitForTimeout(250);}return -1;}
const NAME='Test Appt Cat '+Date.now().toString(36);
const A=await open('A','persona');
await A.tap('#addCat');await A.fill('#cName',NAME);await A.tap('#cSave');
const d=(n)=>A.evaluate(n=>window.__cats.ymd(Date.now()+n*864e5),n);
const d2=await d(2),d1=await d(1);
// add later one first, to check sorting
await A.tap('#addAppt');await A.fill('#aDesc','TEST later appt');await A.fill('#aWhen',d2+'T11:00');await A.tap('#aSave');
await A.tap('#addAppt');ok('form defaults to General vet appointment',await A.inputValue('#aDesc')==='General vet appointment');
await A.fill('#aDesc','TEST sooner appt');await A.fill('#aWhen',d1+'T10:00');await A.tap('#aSave');
const order=await A.$$eval('[data-appt] .when+div',els=>els.map(e=>e.textContent));
ok('cat page Upcoming sorted soonest first',order[0]==='TEST sooner appt'&&order[1]==='TEST later appt',JSON.stringify(order));
await synced(A);
// edit
await A.tap('[data-appt]:has-text("TEST later appt") [data-aedit]');await A.fill('#aDesc','TEST later appt (edited)');await A.tap('#aSave');await synced(A);
// B
const B=await open('B','personb');
let ms=await waitFor(B,n=>{const s=window.__cats.state.items;const c=s.find(x=>x.name===n);return c&&s.filter(x=>x.kind==='appt'&&x.catId===c.id&&x.status==='upcoming').length===2&&s.some(x=>x.description==='TEST later appt (edited)');},NAME);
ok('B sees both appts incl. edit',ms>=0,(ms/1000).toFixed(1)+'s');
await B.waitForTimeout(300);
const home=await B.$$eval('.hcard',els=>els.map(e=>e.innerText));
const mine=home.filter(t=>t.includes(NAME));
ok('home shows test appts, soonest first',mine.length===2&&home.indexOf(mine[0])<home.indexOf(mine[1])&&/, (vet|TEST sooner appt), /.test(mine[0]),JSON.stringify(mine));
const appt1=await B.evaluate(()=>window.__cats.state.items.find(x=>x.description==='TEST sooner appt'));
await B.tap(`.cat:has-text("${NAME}")`);
await B.tap('[data-appt]:has-text("TEST sooner appt") [data-adone]');await B.fill('#dNote','TEST note from visit');await B.tap('#dSave');await synced(B);
ms=await waitFor(A,id=>{const s=window.__cats.state.items;const a=s.find(x=>x.id===id);return a&&a.status==='done'&&s.some(x=>x.kind==='log'&&x.type==='vet'&&x.fromAppt===id);},appt1.id);
ok('Mark done (B) reaches A: status done + vet log',ms>=0,(ms/1000).toFixed(1)+'s');
const vlog=await A.evaluate(id=>window.__cats.state.items.find(x=>x.kind==='log'&&x.fromAppt===id),appt1.id);
ok('vet log prefilled (date=appt time, description + note, by personb)',vlog.at===appt1.at&&vlog.note==='TEST sooner appt\nTEST note from visit'&&vlog.loggedBy==='personb',JSON.stringify({at:vlog.at===appt1.at,note:vlog.note,by:vlog.loggedBy}));
await A.waitForTimeout(300);
ok('done appt hidden from A cat page Upcoming',!(await A.$$eval('[data-appt]',els=>els.map(e=>e.innerText).join('|'))).includes('TEST sooner appt'));
ok('vet visit shows in A log list',(await A.textContent('.log')).includes('TEST note from visit'));
// cancel in A
await A.tap('[data-appt]:has-text("TEST later appt (edited)") [data-acancel]');await synced(A);
ms=await waitFor(B,n=>{const s=window.__cats.state.items;const c=s.find(x=>x.name===n);return c&&!s.some(x=>x.kind==='appt'&&x.catId===c.id&&x.status==='upcoming')&&s.some(x=>x.catId===c.id&&x.status==='cancelled');},NAME);
ok('Cancel (A) reaches B, hidden from Upcoming',ms>=0,(ms/1000).toFixed(1)+'s');
await B.tap('#backBtn');await B.waitForTimeout(300);
ok('B home no longer lists test appts',!(await B.$$eval('.hcard',els=>els.map(e=>e.innerText).join('|'))).includes(NAME));
// tombstone delete: add one more, delete it via Edit > Delete in B, check A
await B.tap(`.cat:has-text("${NAME}")`);await B.tap('#addAppt');await B.fill('#aDesc','TEST to delete');await B.tap('#aSave');await synced(B);
await waitFor(A,()=>window.__cats.state.items.some(x=>x.description==='TEST to delete'));
await B.tap('[data-appt]:has-text("TEST to delete") [data-aedit]');await B.tap('#aDelete');await synced(B);
ms=await waitFor(A,()=>!window.__cats.state.items.some(x=>x.description==='TEST to delete'));ok('appt delete (tombstone) reaches A',ms>=0,(ms/1000).toFixed(1)+'s');
// remove test cat (tombstones cat + its appts + logs)
await A.tap('#backBtn').catch(()=>{});await A.waitForTimeout(200);
if(!(await A.isVisible('#addCat')))await A.evaluate(()=>{history.back();});await A.waitForTimeout(300);
await A.tap(`.cat:has-text("${NAME}")`);await A.tap('#editCat');await A.tap('#cDelete');await synced(A);
ms=await waitFor(B,n=>{const s=window.__cats.state.items;return !s.some(x=>x.name===n)&&!s.some(x=>(x.description||'').startsWith('TEST'));},NAME);ok('test cat + its appts/logs gone on B',ms>=0);
ok('no page errors',errs.length===0,errs.join(' | '));
await b.close();const f=res.filter(x=>!x).length;console.log(f?f+' FAILED':'ALL PASSED ('+res.length+')');process.exit(f?1:0);
})().catch(e=>{console.error(e);process.exit(2);});
