#!/usr/bin/env python3
"""Exercise the real HTTP service and PostgreSQL. Creates/drops only its own temporary DB."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

root = Path(__file__).resolve().parents[1]
binary = root / '.build/debug/starling-documents'
db = 'starling_test_' + uuid.uuid4().hex[:16]
pg_env = dict(os.environ, PGHOST=os.environ.get('PGHOST', '/tmp'))
pg_env.setdefault('PGUSER', os.environ.get('USER', 'postgres'))
subprocess.run(['createdb', db], env=pg_env, check=True)
try:
 with tempfile.TemporaryDirectory(prefix='starling-documents-test-') as directory:
  directory = Path(directory)
  tokens = {name: secrets.token_hex(32) for name in ['alice', 'bob', 'eve', 'other_bob']}
  identities = {token: {'issuer':'local-test','subject':name,'name':name,
                        'email':('bob@example.test' if name=='other_bob' else name+'@example.test')}
                for name, token in tokens.items()}
  identities[tokens['other_bob']]['email'] = None  # cannot accept an invitation with an unverified email
  identity_file=directory/'identities.json'; identity_file.write_text(json.dumps(identities)); identity_file.chmod(0o600)
  with socket.socket() as sock:
   sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
  env=dict(pg_env, PGDATABASE=db, STARLING_DEV_IDENTITIES=str(identity_file), STARLING_HOST='127.0.0.1',
           STARLING_STORAGE_PATH=str(directory/'blobs'), PORT=str(port), PGSSLMODE='disable',
           STARLING_ALLOWED_ORIGINS='https://writer.starling.build')
  log=open(directory/'server.log','w+')
  process=subprocess.Popen([str(binary)],env=env,stdout=log,stderr=log)
  base=f'http://127.0.0.1:{port}'
  checks=0
  def call(method,path,data=None,who='alice',status=200,headers=None,raw=False):
   global checks
   h=dict(headers or {})
   if who:h['Authorization']='Bearer '+tokens.get(who,who)
   if data is not None and not isinstance(data,bytes):data=json.dumps(data).encode();h['Content-Type']='application/json'
   req=urllib.request.Request(base+path,data=data,method=method,headers=h)
   try:
    with urllib.request.urlopen(req,timeout=15) as response: code=response.status;content=response.read();rh=response.headers
   except urllib.error.HTTPError as e: code=e.code;content=e.read();rh=e.headers
   assert code==status,(method,path,code,status,content)
   assert rh.get('Cache-Control')=='no-store'
   checks+=1
   if raw:return content
   return json.loads(content) if content else None
  def sql(statement):
   return subprocess.check_output(['psql','-d',db,'-Atc',statement],env=pg_env,text=True).strip()
  def prepare(doc,content,who='alice',base_revision=None,key=None,status=200):
   return call('POST',f'/v1/documents/{doc}/uploads',{'base_revision_id':base_revision,'size':len(content),
       'sha256':hashlib.sha256(content).hexdigest(),'idempotency_key':key or uuid.uuid4().hex},who=who,status=status)
  def put_commit(upload,content,who='alice',status=200):
   call('PUT',f'/v1/uploads/{upload["id"]}/content',content,who=who)
   return call('POST',f'/v1/uploads/{upload["id"]}/commit',who=who,status=status)
  try:
   for attempt in range(100):
    if process.poll() is not None:raise RuntimeError('server exited')
    try:
     urllib.request.urlopen(base+'/ready',timeout=.5).close();break
    except (OSError,urllib.error.URLError):time.sleep(.1)
   else:raise RuntimeError('server did not start')
   call('GET','/v1/me',who=None,status=401)
   call('GET','/v1/me',who='invalid-token',status=401)
   call('GET','/v1/me',headers={'Origin':'https://evil.example'},status=403)
   call('OPTIONS','/v1/me',who=None,headers={'Origin':'https://writer.starling.build'},status=204)
   users={n:call('GET','/v1/me',who=n)['id'] for n in tokens}
   personal=call('GET','/v1/workspaces')[0]
   call('POST',f'/v1/workspaces/{personal["id"]}/invitations',{'email':'bob@example.test','role':'member'},status=403)
   workspace=call('POST','/v1/workspaces',{'name':'Team'})['id']
   invitation=call('POST',f'/v1/workspaces/{workspace}/invitations',{'email':'bob@example.test','role':'member'})
   call('POST','/v1/invitations/accept',{'token':invitation['token']},who='eve',status=403)
   call('POST','/v1/invitations/accept',{'token':invitation['token']},who='other_bob',status=403)
   call('POST','/v1/invitations/accept',{'token':invitation['token']},who='bob')
   call('POST',f'/v1/workspaces/{workspace}/invitations',{'email':'eve@example.test','role':'admin'},who='bob',status=403)
   call('GET',f'/v1/workspaces/{workspace}/documents',who='eve',status=404)
   doc=call('POST',f'/v1/workspaces/{workspace}/documents',{'name':'Plan.docx','kind':'docx'})['id']
   call('GET',f'/v1/documents/{doc}',who='bob',status=404)
   call('POST',f'/v1/documents/{doc}/grants',{'user_id':users['bob'],'permission':'viewer'})
   call('GET',f'/v1/documents/{doc}',who='bob')
   prepare(doc,b'writer contents',who='bob',status=404)
   call('POST',f'/v1/documents/{doc}/grants',{'user_id':users['eve'],'permission':'viewer'},status=404)
   folder=call('POST',f'/v1/workspaces/{workspace}/folders',{'name':'Planning'})['id']
   assert call('POST',f'/v1/documents/{doc}/move',{'folder_id':folder})['folder_id']==folder
   foreign=call('POST',f'/v1/workspaces/{personal["id"]}/folders',{'name':'Private'})['id']
   call('POST',f'/v1/documents/{doc}/move',{'folder_id':foreign},status=404)
   call('POST',f'/v1/documents/{doc}/move',{'folder_id':folder},who='bob',status=404)
   call('GET',f'/v1/workspaces/{workspace}/documents?offset=-1',status=400)
   assert call('GET',f'/v1/workspaces/{workspace}/documents?offset=200')==[]
   initial=prepare(doc,b'first document',key='first')
   assert prepare(doc,b'first document',key='first')['id']==initial['id']
   prepare(doc,b'other bytes',key='first',status=409)
   call('POST',f'/v1/uploads/{initial["id"]}/commit',status=409)
   call('PUT',f'/v1/uploads/{initial["id"]}/content',b'wrong checksum',status=400)
   call('PUT',f'/v1/uploads/{initial["id"]}/content',b'first document')
   # Identical retry exercises the create-only storage adapter, including S3's 412 response.
   committed=put_commit(initial,b'first document');rev=committed['revision_id']
   assert call('POST',f'/v1/uploads/{initial["id"]}/commit')['revision_id']==rev
   assert call('GET',f'/v1/documents/{doc}/content',who='bob',raw=True)==b'first document'
   call('POST',f'/v1/documents/{doc}/grants',{'user_id':users['bob'],'permission':'editor'})
   # Two uploads from the same base may finish concurrently; exactly one becomes current.
   a=prepare(doc,b'Alice update',base_revision=rev)
   b=prepare(doc,b'Bob update',who='bob',base_revision=rev)
   call('PUT',f'/v1/uploads/{a["id"]}/content',b'Alice update')
   call('PUT',f'/v1/uploads/{b["id"]}/content',b'Bob update',who='bob')
   def race(u,who):
    req=urllib.request.Request(base+f'/v1/uploads/{u["id"]}/commit',method='POST',headers={'Authorization':'Bearer '+tokens[who]})
    try:
     with urllib.request.urlopen(req) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as e:return e.code,json.load(e)
   with concurrent.futures.ThreadPoolExecutor() as pool:
    fa=pool.submit(race,a,'alice');fb=pool.submit(race,b,'bob');results=[fa.result(),fb.result()]
   assert sorted(r[0] for r in results)==[200,409],results
   checks+=1
   winner=next(r[1] for r in results if r[0]==200)
   loser=next(r[1] for r in results if r[0]==409)
   loser_name='alice' if loser['id']==a['id'] else 'bob'
   assert call('GET',f'/v1/uploads/{loser["id"]}/content',who=loser_name,raw=True) in [b'Alice update',b'Bob update']
   history=call('GET',f'/v1/documents/{doc}/revisions');assert len(history)==2
   restored=call('POST',f'/v1/documents/{doc}/revisions/{rev}/restore',{'base_revision_id':winner['revision_id']})
   assert call('GET',f'/v1/documents/{doc}/content',raw=True)==b'first document'
   call('POST',f'/v1/documents/{doc}/revisions/{rev}/restore',{'base_revision_id':winner['revision_id']},status=409)
   # A revision belonging to another document must never be usable here.
   other=call('POST',f'/v1/workspaces/{workspace}/documents',{'name':'Other','kind':'xlsx'})['id']
   call('GET',f'/v1/documents/{other}/revisions/{rev}/content',status=404)
   link=call('POST',f'/v1/documents/{doc}/shares',{})
   assert call('GET',f'/v1/shares/{link["token"]}/content',who=None,raw=True)==b'first document'
   call('DELETE',f'/v1/documents/{doc}/shares/{link["id"]}')
   call('GET',f'/v1/shares/{link["token"]}/content',who=None,status=404)
   # Revocation after an upload was authorized must block commit and further reads.
   pending=prepare(doc,b'pending',who='bob',base_revision=restored['id'])
   call('PUT',f'/v1/uploads/{pending["id"]}/content',b'pending',who='bob')
   call('DELETE',f'/v1/documents/{doc}/grants/{users["bob"]}')
   call('POST',f'/v1/uploads/{pending["id"]}/commit',who='bob',status=404)
   call('GET',f'/v1/documents/{doc}/content',who='bob',status=404)
   # Trashing invalidates public links; restoration doesn't revive them.
   link=call('POST',f'/v1/documents/{doc}/shares',{})
   call('DELETE',f'/v1/documents/{doc}')
   call('GET',f'/v1/documents/{doc}',status=404)
   call('GET',f'/v1/shares/{link["token"]}',who=None,status=404)
   call('POST',f'/v1/documents/{doc}/restore')
   call('GET',f'/v1/shares/{link["token"]}',who=None,status=404)
   call('DELETE',f'/v1/workspaces/{workspace}/members/{users["bob"]}')
   call('POST','/v1/invitations/accept',{'token':invitation['token']},who='bob',status=404)
   # Quota reservations include uncommitted/conflicting uploads; cleanup releases once.
   sql(f"UPDATE uploads SET expires_at=now()-interval '1 second' WHERE state IN ('pending','uploaded','conflict')")
   subprocess.run([str(binary),'--cleanup'],env=env,check=True,stdout=subprocess.DEVNULL)
   assert sql(f"SELECT reserved_bytes FROM workspaces WHERE id='{workspace}'")=='0'
   subprocess.run([str(binary),'--cleanup'],env=env,check=True,stdout=subprocess.DEVNULL)
   assert sql(f"SELECT reserved_bytes FROM workspaces WHERE id='{workspace}'")=='0'
   sql(f"UPDATE workspaces SET quota_bytes=used_bytes WHERE id='{workspace}'")
   prepare(doc,b'quota',base_revision=restored['id'],status=413)
   activity=call('GET',f'/v1/workspaces/{workspace}/activity');assert any(x['event']=='revision.committed' for x in activity)
   call('GET',f'/v1/workspaces/{workspace}/activity',who='eve',status=404)
   admin_invite=call('POST',f'/v1/workspaces/{workspace}/invitations',{'email':'eve@example.test','role':'admin'})
   call('POST','/v1/invitations/accept',{'token':admin_invite['token']},who='eve')
   call('GET',f'/v1/documents/{doc}',who='eve',status=404)
   call('POST',f'/v1/documents/{doc}/admin-recovery',who='eve')
   call('GET',f'/v1/documents/{doc}',who='eve')
   call('GET',f'/v1/documents/{doc}',status=404)
   call('POST',f'/v1/documents/{doc}/admin-recovery')
   assert any(a['event']=='document.admin_recovery' for a in call('GET',f'/v1/workspaces/{workspace}/activity'))
   # Restart proves persistence and migration idempotence.
   process.terminate();process.wait(timeout=10)
   process=subprocess.Popen([str(binary)],env=env,stdout=log,stderr=log)
   for _ in range(100):
    try:urllib.request.urlopen(base+'/ready',timeout=.5).close();break
    except OSError:time.sleep(.1)
   assert call('GET',f'/v1/documents/{doc}/content',raw=True)==b'first document'
   print(f'PASS: {checks} HTTP checks, concurrent saves, permission revocation, quota cleanup, and restart persistence')
  except BaseException:
   log.flush();log.seek(0);print(log.read());raise
  finally:
   if process.poll() is None:process.terminate();process.wait(timeout=10)
   log.close()
finally:
 subprocess.run(['dropdb',db],env=pg_env,check=True)
