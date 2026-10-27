// Local stand-in for here.now: serves ./site and emulates the public Site Data endpoint
// /.herenow/data/<collection> (GET list w/ cursor, POST, PATCH /:id). Usage: node test/mock-server.js [port]
const http=require('http'),fs=require('fs'),path=require('path');
const ROOT=path.join(__dirname,'..','site'),PORT=+process.argv[2]||8787;
const recs=[];let n=0;
const types={'.html':'text/html','.js':'text/javascript','.png':'image/png','.webmanifest':'application/manifest+json','.json':'application/json'};
http.createServer((q,s)=>{const u=new URL(q.url,'http://x');const m=u.pathname.match(/^\/\.herenow\/data\/[a-z][a-z0-9_]*(?:\/([^/]+))?$/);
  const send=(c,o)=>{s.writeHead(c,{'content-type':'application/json'});s.end(JSON.stringify(o));};
  if(m){let b='';q.on('data',d=>b+=d);q.on('end',()=>{
    if(q.method==='GET'&&!m[1]){const lim=+u.searchParams.get('limit')||100,off=+(u.searchParams.get('cursor')||0);const page=recs.slice(off,off+lim);
      return send(200,{records:page,nextCursor:off+lim<recs.length?String(off+lim):null});}
    if(q.method==='POST'&&!m[1]){const r={id:'r'+(++n),data:JSON.parse(b),createdAt:new Date().toISOString(),updatedAt:new Date().toISOString()};recs.push(r);return send(201,{record:r});}
    if(q.method==='PATCH'&&m[1]){const r=recs.find(x=>x.id===m[1]);if(!r)return send(404,{error:'not found'});Object.assign(r.data,JSON.parse(b));r.updatedAt=new Date().toISOString();return send(200,{record:r});}
    if(q.method==='DELETE'&&m[1])return send(403,{error:'owner only'});
    send(405,{error:'method'});});return;}
  if(u.pathname==='/__records')return send(200,recs);
  let p=path.join(ROOT,decodeURIComponent(u.pathname));if(u.pathname.endsWith('/'))p=path.join(p,'index.html');
  if(p.includes('/.herenow/'))return send(404,{});
  fs.readFile(p,(e,d)=>{if(e){s.writeHead(404);return s.end();}s.writeHead(200,{'content-type':types[path.extname(p)]||'application/octet-stream'});s.end(d);});
}).listen(PORT,()=>console.log('mock on http://localhost:'+PORT));
