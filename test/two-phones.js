// Two-phone round-trip test: APP_URL=http://localhost:8787/ node test/two-phones.js
// Adds a test cat + entries on "phone A", checks they appear on "phone B" and vice versa,
// then deletes the test cat in-app (tombstones). Live runs should be followed by tools/clear-data.sh.
const {chromium}=require(__dirname+'/node_modules/playwright-core');
const URL_=process.env.APP_URL||'http://localhost:8787/'+require(__dirname+'/../secret-config.json').path_token+'/';
const SHOTS=__dirname+'/../screenshots/';const shots=process.env.SHOTS!=='0';
const res=[];const ok=(n,p,x='')=>{res.push(p);console.log((p?'PASS ':'FAIL ')+n+(x?' — '+x:''));};
(async()=>{
const b=await chromium.launch({executablePath:'/usr/bin/google-chrome',args:['--no-sandbox']});
const phone={viewport:{width:393,height:851},deviceScaleFactor:2,isMobile:true,hasTouch:true,timezoneId:'America/Chicago',
  userAgent:'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36'};
const errs=[];
async function open(l){const ctx=await b.newContext(phone);const p=await ctx.newPage();p.on('pageerror',e=>errs.push(l+': '+e));
  p.on('console',m=>{if(m.type()==='error')errs.push(l+': '+m.text());});p.on('dialog',d=>d.accept());await p.goto(URL_);return {ctx,p};}
const synced=p=>p.waitForFunction(()=>{const d=window.__cats.store.debug();return d.status==='ok'&&d.dirty.length===0&&d.synced;},null,{timeout:30000});
async function waitFor(p,fn,arg,ms=25000){const t0=Date.now();while(Date.now()-t0<ms){if(await p.evaluate(fn,arg))return Date.now()-t0;await p.waitForTimeout(250);}return -1;}
const NAME='Test Kitty '+Date.now().toString(36);
const A=await open('A');await A.p.waitForTimeout(600);
ok('name picker on first open',await A.p.evaluate(()=>document.querySelector('#whoDlg').open));
if(shots)await A.p.screenshot({path:SHOTS+'01-who.png'});
await A.p.tap('[data-who="persona"]');await synced(A.p);
const base=await A.p.evaluate(()=>window.__cats.state.items.length);
ok('starts empty / loads',true,base+' items already on server');
if(shots&&base===0)await A.p.screenshot({path:SHOTS+'02-empty.png'});
// add cat
await A.p.tap('#addCat');await A.p.fill('#cName',NAME);await A.p.fill('#cAge','3');await A.p.selectOption('#cSex','female');await A.p.fill('#cColor','Tabby');
await A.p.tap('#cSave');
ok('cat view opens after add',(await A.p.textContent('#title'))===NAME);
// weight
await A.p.tap('[data-log="weight"]');await A.p.fill('#lWeight','9.4');
const d1=await A.p.evaluate(()=>window.__cats.ymd(Date.now()-14*864e5));await A.p.fill('#lDate',d1);await A.p.tap('#lSave');
// symptom
await A.p.tap('[data-log="symptom"]');
ok('symptom dialog shows vet line',await A.p.isVisible('#lFlag'));
await A.p.fill('#lNote','Sneezed a few times after breakfast');await A.p.tap('#lSave');
await A.p.waitForTimeout(400);
ok('symptom entry shows flag line',(await A.p.textContent('.log')).includes('If this seems concerning, check with your vet.'));
await synced(A.p);
const recs=await A.p.evaluate(async()=>(await (await fetch(window.__cats.store.api+'?limit=100',{cache:'no-store'})).json()).records.length);
ok('records landed in shared storage',recs>=base+3,recs+' records');
// B
const B=await open('B');await B.p.waitForTimeout(600);await B.p.tap('[data-who="personb"]');
let ms=await waitFor(B.p,n=>window.__cats.state.items.some(x=>x.kind==='cat'&&x.name===n),NAME);ok('B sees the cat',ms>=0,(ms/1000).toFixed(1)+'s');
const bl=await B.p.evaluate(n=>{const s=window.__cats.state.items;const c=s.find(x=>x.name===n);return s.filter(x=>x.catId===c.id).map(x=>({t:x.type,by:x.loggedBy,w:x.weightLb}));},NAME);
ok('B sees both entries with loggedBy=persona',bl.length===2&&bl.every(x=>x.by==='persona'),JSON.stringify(bl));
await B.p.tap(`.cat:has-text("${NAME}")`);
await B.p.tap('[data-log="weight"]');await B.p.fill('#lWeight','9.6');await B.p.tap('#lSave');
await B.p.tap('[data-log="food"]');await B.p.fill('#lNote','Ate full bowl of wet food');await B.p.tap('#lSave');
await B.p.waitForTimeout(300);
ok('B chart has 2 points',await B.p.evaluate(()=>document.querySelectorAll('svg.chart circle').length)===2);
if(shots)await B.p.screenshot({path:SHOTS+'03-cat-personb.png',fullPage:true});
ms=await waitFor(A.p,n=>{const s=window.__cats.state.items;const c=s.find(x=>x.name===n);return c&&s.filter(x=>x.catId===c.id).length===4;},NAME);
ok('A sees B’s weight + food entries',ms>=0,(ms/1000).toFixed(1)+'s');
const byPersonB=await A.p.evaluate(()=>window.__cats.state.items.filter(x=>x.kind==='log'&&x.loggedBy==='personb').length);
ok('loggedBy=personb preserved',byPersonB>=2);
await A.p.waitForTimeout(500);
ok('A chart shows 2 points',await A.p.evaluate(()=>document.querySelectorAll('svg.chart circle').length)===2);
// edit in A, delete in B
await A.p.tap('li[data-entry]:has-text("Ate full bowl")');await A.p.fill('#lNote','Ate full bowl of wet food + treats');await A.p.tap('#lSave');
ms=await waitFor(B.p,()=>window.__cats.state.items.some(x=>x.note==='Ate full bowl of wet food + treats'&&x.lastEditedBy==='persona'));ok('edit in A reaches B',ms>=0,(ms/1000).toFixed(1)+'s');
await B.p.waitForTimeout(400);await B.p.tap('li[data-entry]:has-text("Sneezed")');await B.p.tap('#lDelete');
ms=await waitFor(A.p,()=>!window.__cats.state.items.some(x=>x.note&&x.note.startsWith('Sneezed')));ok('delete in B reaches A',ms>=0,(ms/1000).toFixed(1)+'s');
// timestamps
const at=await A.p.evaluate(()=>{const l=window.__cats.state.items.find(x=>x.type==='food');return document.querySelector(`[data-entry="${l.id}"] .sub`).textContent;});
ok('entry shows CT time + who',/CT · by Person B/.test(at),at);
await A.p.tap('#backBtn');await A.p.waitForTimeout(300);
if(shots)await A.p.screenshot({path:SHOTS+'04-home-persona.png'});
// reload persistence
await A.p.reload();await synced(A.p);
ok('A reload keeps data + name',await A.p.evaluate(n=>window.__cats.me==='persona'&&window.__cats.state.items.some(x=>x.name===n),NAME));
// cleanup: delete cat (tombstones cat + its logs)
await A.p.tap(`.cat:has-text("${NAME}")`);await A.p.tap('#editCat');await A.p.tap('#cDelete');await synced(A.p);
ms=await waitFor(B.p,n=>{const s=window.__cats.state.items;return !s.some(x=>x.name===n)&&!s.some(x=>x.kind==='log'&&!s.some(c=>c.id===x.catId));},NAME);ok('cat delete (with its logs) reaches B',ms>=0);
const real=await B.p.evaluate(()=>window.__cats.state.items.filter(x=>x.kind==='cat').map(x=>x.name).sort().join(','));
if(process.env.EXPECT_CATS)ok('real cats still there after test',real===process.env.EXPECT_CATS,real);
ok('no page errors',errs.length===0,errs.join(' | '));
await b.close();const f=res.filter(x=>!x).length;console.log(f?f+' FAILED':'ALL PASSED ('+res.length+')');process.exit(f?1:0);
})().catch(e=>{console.error(e);process.exit(2);});
