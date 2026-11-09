"""Publish source and release assets. Credentials are read from an external file.
Usage: python tools/publish_release.py --credentials PATH --phase push|release
"""
import argparse,base64,json,os,re,subprocess,sys
from pathlib import Path
import requests
ROOT=Path(__file__).resolve().parents[1]
REPOS={'github':('HighnessRK','liuguang','https://api.github.com'), 'gitee':('highnesssrk','liuguang','https://gitee.com/api/v5')}
def credentials(path):
    text=Path(path).read_text(encoding='utf-8-sig')
    github=re.search(r'(?:github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+)',text)
    gitee=re.search(r'GITEE_TOKEN\s*[:：=]\s*[\"\']?([A-Za-z0-9_-]+)',text,re.I)
    if not github or not gitee: raise RuntimeError('Credential labels not recognized')
    return {'github':github.group(0),'gitee':gitee.group(1)}
def session(provider,token):
    s=requests.Session()
    if provider=='github':s.headers.update(Authorization='Bearer '+token,Accept='application/vnd.github+json')
    else:s.params={'access_token':token}
    return s
def require(response):
    if not response.ok: raise RuntimeError('Remote API returned HTTP '+str(response.status_code))
    return response.json()
def github_sync(token):
    s=session('github',token)
    api='https://api.github.com/repos/HighnessRK/liuguang'
    head=require(s.get(api+'/git/ref/heads/main',timeout=30))['object']['sha']
    commit=require(s.get(api+'/git/commits/'+head,timeout=30))
    tree=require(s.get(api+'/git/trees/'+commit['tree']['sha'],params={'recursive':'1'},timeout=30))
    remote={v['path']:v['sha'] for v in tree['tree'] if v['type']=='blob'}
    rows=subprocess.check_output(['git','ls-tree','-rz','HEAD'],cwd=ROOT).split(b'\0')
    local={}
    changes=[]
    for row in filter(None,rows):
        meta,path=row.split(b'\t',1); mode,kind,sha=meta.decode().split();path=path.decode()
        local[path]=sha
        if remote.get(path)==sha:continue
        data=subprocess.check_output(['git','show','HEAD:'+path],cwd=ROOT)
        blob=require(s.post(api+'/git/blobs',json={'content':base64.b64encode(data).decode(),'encoding':'base64'},timeout=45))
        changes.append({'path':path,'mode':mode,'type':'blob','sha':blob['sha']})
    for path in remote.keys()-local.keys():changes.append({'path':path,'mode':'100644','type':'blob','sha':None})
    if not changes:
        print('GitHub source already current',flush=True);return
    tree=require(s.post(api+'/git/trees',json={'base_tree':commit['tree']['sha'],'tree':changes},timeout=45))
    new=require(s.post(api+'/git/commits',json={'message':'Update V1.0.0 source and validation','tree':tree['sha'],'parents':[head]},timeout=30))
    require(s.patch(api+'/git/refs/heads/main',json={'sha':new['sha'],'force':False},timeout=30))
    print('GitHub source synchronized through Git Data API:',len(changes),'files',flush=True)
def push(tokens):
    cache=ROOT/'tools/.cache';cache.mkdir(exist_ok=True)
    helper=cache/'git-askpass.py'
    helper.write_text("import os,sys\nprint(os.environ['LIUGUANG_GIT_USER'] if 'username' in sys.argv[1].lower() else os.environ['LIUGUANG_GIT_TOKEN'])\n")
    cmd=cache/'git-askpass.cmd';cmd.write_text('@"'+sys.executable+'" "%~dp0git-askpass.py" %*\n')
    for provider,(owner,name,_) in REPOS.items():
        if provider=='github':
            github_sync(tokens[provider]);continue
        url=f'https://{ "github.com" if provider=="github" else "gitee.com"}/{owner}/{name}.git'
        remote='origin' if provider=='github' else 'gitee'
        if subprocess.run(['git','remote','get-url',remote],cwd=ROOT,capture_output=True).returncode:
            subprocess.run(['git','remote','add',remote,url],cwd=ROOT,check=True)
        env=os.environ.copy();env.update(GIT_ASKPASS=str(cmd),GIT_TERMINAL_PROMPT='0',LIUGUANG_GIT_USER='x-access-token' if provider=='github' else owner,LIUGUANG_GIT_TOKEN=tokens[provider])
        print('Pushing source:',provider,flush=True)
        r=subprocess.run(['git','-c','credential.helper=','push','--set-upstream',remote,'main'],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
        if r.returncode:
            clean = r.stderr
            for value in tokens.values(): clean = clean.replace(value, '[REDACTED]')
            print(clean[-1800:], file=sys.stderr)
            raise RuntimeError(provider+' source push failed')
        print('Source push complete:',provider,flush=True)
def release(tokens):
    notes=(ROOT/'CHANGELOG.md').read_text(encoding='utf8')
    results={}
    for provider,(owner,name,api) in REPOS.items():
        s=session(provider,tokens[provider]);endpoint=f'{api}/repos/{owner}/{name}/releases'
        response=s.get(endpoint,timeout=30);require(response)
        existing=next((v for v in response.json() if v.get('tag_name')=='v1.0.0'),None)
        body=notes+'\n\nGitHub 下载备用入口：https://github.com/HighnessRK/liuguang/releases/tag/v1.0.0\n'
        payload={'tag_name':'v1.0.0','target_commitish':'main','name':'琉光 V1.0.0','body':body,'prerelease':False}
        if provider=='github':payload['draft']=True
        print('Preparing release:',provider,flush=True)
        item=existing or require(s.post(endpoint,json=payload,timeout=30) if provider=='github' else s.post(endpoint,data=payload,timeout=30))
        release_id=item['id']
        for filename in ['liuguang-v1.0.0-arm64.apk','SHA256.txt']:
            path=ROOT/'dist'/filename
            print('Uploading',provider,filename,flush=True)
            if provider=='github':
                assets=require(s.get(endpoint+f'/{release_id}/assets',timeout=30))
                match=next((a for a in assets if a['name']==filename),None)
                if match:
                    # Never silently replace a different binary of an existing published version.
                    if not item.get('draft'): raise RuntimeError('Published asset already exists')
                    require_delete=s.delete(f'{api}/repos/{owner}/{name}/releases/assets/{match["id"]}',timeout=30)
                    if not require_delete.ok:raise RuntimeError('Could not replace draft asset')
                upload=item['upload_url'].split('{')[0]
                with path.open('rb') as f:
                    uploaded=s.post(upload,params={'name':filename},data=f,headers={'Content-Type':'application/vnd.android.package-archive' if filename.endswith('.apk') else 'text/plain'},timeout=180)
                require(uploaded)
            else:
                with path.open('rb') as f:
                    uploaded=s.post(endpoint+f'/{release_id}/attach_files',files={'file':(filename,f,'application/octet-stream')},timeout=180)
                if not uploaded.ok:
                    print('Gitee attachment endpoint status:',uploaded.status_code,flush=True)
                    results['gitee_attachment_status']=uploaded.status_code
                    break
        if provider=='github':
            item=require(s.patch(endpoint+f'/{release_id}',json={'draft':False},timeout=30))
        results[provider]={'id':release_id,'url':item.get('html_url') or f'https://gitee.com/{owner}/{name}/releases/tag/v1.0.0'}
        print('Release prepared:',provider,flush=True)
    (ROOT/'tools/.cache/release-results.json').write_text(json.dumps(results))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--credentials',required=True);parser.add_argument('--phase',choices=['push','release'],required=True);args=parser.parse_args()
    try:
        tokens=credentials(args.credentials)
        (push if args.phase=='push' else release)(tokens)
    except Exception as e:
        print('Publish failed:',type(e).__name__,str(e) if isinstance(e,RuntimeError) else '(details suppressed)',file=sys.stderr)
        raise SystemExit(1)
