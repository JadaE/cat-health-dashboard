#!/usr/bin/env python3
# Prepare (NOT run) a storage-name rotation: write secret-config.next.json with a NEW random collection
# name (and, with --token, a new path token), the old collection moved to "retired_collections", slug
# unchanged. The new values are generated here and go straight into a 0600 file under a 0700 folder
# (<app dir>/.rotation/). They are never printed, logged or passed on a command line, and
# secret-config.json is only read, never written. Nothing is published and no network call is made.
# Usage: python3 tools/prepare-rotation.py [--token]   generate .rotation/secret-config.next.json
#        python3 tools/prepare-rotation.py --check     check it exists, file 0600, folder 0700 (no values shown)
# Options: CAT_HEALTH_DIR=<dir> (app dir; default is the repo root). Refuses to overwrite an existing file.
# The switch itself (move the file over secret-config.json, publish, verify) is a separate, approved step.
import base64,json,os,pathlib,re,secrets,stat,sys
os.umask(0o077)
D=pathlib.Path(os.environ.get('CAT_HEALTH_DIR') or pathlib.Path(__file__).resolve().parent.parent)
CFG=D/'secret-config.json'; OUTD=D/'.rotation'; OUT=OUTD/'secret-config.next.json'
NAME=re.compile(r'[a-z][a-z0-9_]*')
def die(msg,code=2):print('prepare-rotation: '+msg,file=sys.stderr);sys.exit(code)
def mode(p):return stat.S_IMODE(os.lstat(p).st_mode)
def check_dir():
  st=os.lstat(OUTD)
  if not stat.S_ISDIR(st.st_mode):die('.rotation exists and is not a real folder')
  if st.st_uid!=os.getuid():die('.rotation is not owned by this account')
  if mode(OUTD)!=0o700:die('.rotation is %o, must be 700'%mode(OUTD))
def check_out(prev=None):
  check_dir()
  if not OUT.exists() and not OUT.is_symlink():die('.rotation/secret-config.next.json is missing')
  st=os.lstat(OUT)
  if not stat.S_ISREG(st.st_mode):die('.rotation/secret-config.next.json is not a regular file')
  if mode(OUT)!=0o600:die('.rotation/secret-config.next.json is %o, must be 600'%mode(OUT))
  try:n=json.loads(OUT.read_text())
  except Exception:die('.rotation/secret-config.next.json is not valid JSON')
  for k in ('path_token','collection'):
    if not isinstance(n.get(k),str) or not n[k]:die('next config has no '+k)
  if not NAME.fullmatch(n['collection']):die('next collection name has a bad format')
  r=n.get('retired_collections',[])
  if not isinstance(r,list) or n['collection'] in r:die('next config retired_collections is invalid')
  if prev is not None and n['collection']==prev:die('next collection equals the current one')
  return n
def main():
  args=sys.argv[1:]
  if args==['--check']:
    check_out(); print('OK: .rotation/secret-config.next.json present (file 0600, folder 0700); values not shown'); return
  if args not in ([],['--token']):die('usage: prepare-rotation.py [--token] | --check')
  try:cfg=json.loads(CFG.read_text())
  except Exception:die('secret-config.json missing, unreadable or not JSON')
  if mode(CFG)&0o077:die('secret-config.json is group/world accessible; chmod 600 it first')
  old=cfg.get('collection'); tok=cfg.get('path_token')
  if not isinstance(old,str) or not NAME.fullmatch(old):die('current collection missing or bad format')
  if not isinstance(tok,str) or not tok:die('current path_token missing')
  retired=cfg.get('retired_collections') or []
  if not isinstance(retired,list) or not all(isinstance(r,str) and NAME.fullmatch(r) for r in retired):die('current retired_collections is invalid')
  if OUTD.exists() or OUTD.is_symlink():check_dir()
  else:OUTD.mkdir(mode=0o700); os.chmod(OUTD,0o700)
  if OUT.exists() or OUT.is_symlink():die('.rotation/secret-config.next.json already exists; move it away first (not overwritten)')
  b32=lambda:base64.b32encode(secrets.token_bytes(20)).decode().lower()  # 160 bits -> 32 chars [a-z2-7]
  new='c'+b32()
  while new==old or new in retired:new='c'+b32()
  nxt=dict(cfg); nxt['collection']=new
  nxt['retired_collections']=[r for r in retired if r!=old]+[old]
  rot_tok='--token' in args
  if rot_tok:
    t=b32()
    while t==tok:t=b32()
    nxt['path_token']=t
  data=(json.dumps(nxt,indent=2)+'\n').encode()
  fd=os.open(OUT,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
  try:
    os.write(fd,data); os.fsync(fd)
  finally:os.close(fd)
  os.chmod(OUT,0o600)
  check_out(prev=old)
  print('OK: wrote .rotation/secret-config.next.json (file 0600, folder 0700); new collection generated, '
        'path token '+('rotated' if rot_tok else 'unchanged')+'; values not shown. secret-config.json untouched.')
if __name__=='__main__':
  try:main()
  except SystemExit:raise
  except Exception as e:die('failed ('+type(e).__name__+'); no values shown',1)
