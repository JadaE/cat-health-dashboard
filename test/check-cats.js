// Fresh browser: confirm your cats + notes render at the app URL. APP_URL=... CAT_NAMES='Cat 1,Cat 2' node test/check-cats.js
// CAT_NAMES: comma-separated names of cats that already exist in your data (defaults are placeholders).
const CATS=(process.env.CAT_NAMES||'Cat 1,Cat 2').split(',').map(s=>s.trim()).filter(Boolean);
const {chromium}=require(__dirname+'/node_modules/playwright-core');
const cfg=require(__dirname+'/../secret-config.json');
const URL_=process.env.APP_URL||`https://${cfg.slug}.here.now/${cfg.path_token}/`;
(async()=>{const b=await chromium.launch({executablePath:'/usr/bin/google-chrome',args:['--no-sandbox']});
const p=await (await b.newContext({viewport:{width:393,height:851},deviceScaleFactor:2,isMobile:true,hasTouch:true,timezoneId:'America/Chicago'})).newPage();
const errs=[];p.on('pageerror',e=>errs.push(String(e)));const ext=[];
p.on('request',r=>{if(!r.url().startsWith(new URL(URL_).origin))ext.push(r.url());});
await p.goto(URL_);await p.tap('[data-who="persona"]');await p.waitForSelector(`.cat:has-text("${CATS[CATS.length-1]}")`,{timeout:20000});
console.log('home:',JSON.stringify(await p.$$eval('.cat',els=>els.map(e=>e.innerText.replace(/\n/g,' | ')))));
if(process.env.SHOT)await p.screenshot({path:__dirname+'/../screenshots/07-new-home.png'});
for(const n of CATS){await p.tap(`.cat:has-text("${n}")`);await p.waitForTimeout(300);
  console.log(n+':',await p.textContent('.top .sub'),'| notes:',JSON.stringify(await p.textContent('main section .n')));await p.tap('#backBtn');await p.waitForTimeout(300);}
console.log('referrer policy (document):',await p.evaluate(()=>document.querySelector('meta[name=referrer]').content),'| robots meta:',await p.evaluate(()=>document.querySelector('meta[name=robots]').content));
console.log('third-party requests:',ext.length?ext:'none');console.log('page errors:',errs.length?errs:'none');await b.close();})();
