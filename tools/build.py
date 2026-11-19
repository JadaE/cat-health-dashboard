# Build the publishable site/ from src/ + tools/store.js + secret-config.json (no npm, no bundler).
#   site/index.html            blank "Nothing here" page (so the root never shows a file listing)
#   site/robots.txt            Disallow everything
#   site/_headers              X-Robots-Tag / Referrer-Policy rules (only if here.now honors it)
#   site/.herenow/data.json    Site Data manifest; the collection name is secret. Optional
#                              "retired_collections" in secret-config.json are listed there with
#                              owner-only access (kept as an owner-only backup after a rotation).
#   site/<path_token>/...      the actual app
# Output is private: dirs 0700, files 0600, so other accounts on a shared machine can't read the
# collection name (data.json, app index.html) or list the path-token directory name.
# Default app dir is this repo (relative to this file); CAT_HEALTH_DIR optionally overrides it.
import json,os,pathlib,re,shutil,sys
os.umask(0o077)
D=pathlib.Path(os.environ.get('CAT_HEALTH_DIR') or pathlib.Path(__file__).resolve().parent.parent)
cfg=json.loads((D/'secret-config.json').read_text())
tok,coll=cfg['path_token'],cfg['collection']
NAME=re.compile(r'[a-z][a-z0-9_]*')
def die(msg):print('build refused: '+msg,file=sys.stderr);sys.exit(2)
# Retired collection names never reach the app JS or any public file; they only go in the
# manifest with owner-only access. Errors never print a name.
retired=cfg.get('retired_collections',[])
if retired is None:retired=[]
if not isinstance(retired,list):die('retired_collections must be a list')
for i,r in enumerate(retired):
  if not isinstance(r,str) or not NAME.fullmatch(r):die(f'retired_collections[{i}] must match [a-z][a-z0-9_]*')
  if r==coll:die(f'retired_collections[{i}] equals the live collection')
if len(set(retired))!=len(retired):die('retired_collections has duplicates')
out=D/'site'
if out.exists():shutil.rmtree(out)
(out/'.herenow').mkdir(parents=True);app=out/tok;app.mkdir()
src=(D/'src/app.html').read_text();store=(D/'tools/store.js').read_text()
assert src.count('/*STORE*/')==1 and store.count('/*DATA_API*/')==1
(app/'index.html').write_text(src.replace('/*STORE*/',store.replace('/*DATA_API*/','/.herenow/data/'+coll)))
for r in retired:
  if r in (app/'index.html').read_text():die('a retired collection name ended up in the app page')
for f in (D/'src/assets').iterdir():shutil.copy(f,app/f.name)
shutil.copy(D/'src/root.html',out/'index.html')
(out/'robots.txt').write_text('User-agent: *\nDisallow: /\n')
if (D/'src/_headers').exists():shutil.copy(D/'src/_headers',out/'_headers')
FIELDS={
  "item_id":{"type":"string","required":True,"maxLength":64,"trim":True},
  "payload":{"type":"object"},
  "changed_at":{"type":"number","required":True,"minimum":0},
  "deleted":{"type":"boolean","default":False},
  "device":{"type":"string","maxLength":40}}
PUBLIC_ACCESS={"read":"public","insert":"public","update":"public","delete":"owner"}
OWNER_ONLY={"read":"owner","insert":"owner","update":"owner","delete":"owner"}
def coll_def(live):
  d={"fields":FIELDS,"access":dict(PUBLIC_ACCESS if live else OWNER_ONLY)}
  if live:d.update({"publicMutation":"open","rateLimit":"120/minute/ip"})
  return d
manifest={"collections":{coll:coll_def(True),**{r:coll_def(False) for r in retired}}}
(out/'.herenow/data.json').write_text(json.dumps(manifest,indent=2))
# shutil.copy keeps source modes, so set every mode explicitly rather than trusting umask alone
for p in [out,*out.rglob('*')]:os.chmod(p,0o700 if p.is_dir() else 0o600)
print('built site/ (app under the secret path; %d retired collection(s), owner-only)'%len(retired))
