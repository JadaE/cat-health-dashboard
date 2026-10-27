# Build the publishable site/ from src/ + tools/store.js + secret-config.json (no npm, no bundler).
#   site/index.html            blank "Nothing here" page (so the root never shows a file listing)
#   site/robots.txt            Disallow everything
#   site/_headers              X-Robots-Tag / Referrer-Policy rules (only if here.now honors it)
#   site/.herenow/data.json    Site Data manifest; the collection name is secret
#   site/<path_token>/...      the actual app
import json,pathlib,shutil
D=pathlib.Path(__file__).resolve().parent.parent;cfg=json.loads((D/'secret-config.json').read_text())
tok,coll=cfg['path_token'],cfg['collection']
out=D/'site'
if out.exists():shutil.rmtree(out)
(out/'.herenow').mkdir(parents=True);app=out/tok;app.mkdir()
src=(D/'src/app.html').read_text();store=(D/'tools/store.js').read_text()
assert src.count('/*STORE*/')==1 and store.count('/*DATA_API*/')==1
(app/'index.html').write_text(src.replace('/*STORE*/',store.replace('/*DATA_API*/','/.herenow/data/'+coll)))
for f in (D/'src/assets').iterdir():shutil.copy(f,app/f.name)
shutil.copy(D/'src/root.html',out/'index.html')
(out/'robots.txt').write_text('User-agent: *\nDisallow: /\n')
if (D/'src/_headers').exists():shutil.copy(D/'src/_headers',out/'_headers')
manifest={"collections":{coll:{"fields":{
  "item_id":{"type":"string","required":True,"maxLength":64,"trim":True},
  "payload":{"type":"object"},
  "changed_at":{"type":"number","required":True,"minimum":0},
  "deleted":{"type":"boolean","default":False},
  "device":{"type":"string","maxLength":40}},
  "access":{"read":"public","insert":"public","update":"public","delete":"owner"},
  "publicMutation":"open","rateLimit":"120/minute/ip"}}}
(out/'.herenow/data.json').write_text(json.dumps(manifest,indent=2))
print('built site/ (app under the secret path)')
