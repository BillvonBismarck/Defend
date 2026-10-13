"""Native acceptance with fresh output files and temporary, non-shipped QA entrypoint."""
import argparse,json,subprocess,re,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('scene',choices=['map','activation','towers','placement','placement_confirm','stress','tactical'])
p.add_argument('--frames',type=int,default=180);a=p.parse_args()
if a.scene in ('map','activation') and a.frames<500:a.frames=600
dest=ROOT/'validation/defense/review3-20261013';dest.mkdir(exist_ok=True)
test=ROOT/'scripts/__review3_qa.lua';name=a.scene
for suffix in ('.json','.png','-summary.json'): (dest/f'{name}{suffix}').unlink(missing_ok=True)
test.write_text(f'QA_SCENE="{name}"\nQA_FINISH={a.frames-10}\n'+(ROOT/'validation/defense/review3_runtime.lua').read_text('utf8'),encoding='utf8')
argv=[str(ROOT/'.cli/UrhoXRuntime.exe'),'main.lua',f'-tapcode_dir={ROOT}','-tool_mode','-validate',f'-validate-frames={a.frames}',
    '-validate-timeout=50',f'-validate-output={dest}/{name}.json',f'-screenshot={dest}/{name}.png',
    f'-screenshot-frame={a.frames-5}','-validate-spike-threshold=500','-x','1280','-y','720','-log','info','-validate-test=__review3_qa.lua']
try:
    proc=subprocess.run(argv,cwd=ROOT/'.cli',capture_output=True,timeout=60)
    log=proc.stdout+proc.stderr;(dest/f'{name}.log').write_bytes(log)
finally:
    test.unlink(missing_ok=True);Path(str(test)+'.meta').unlink(missing_ok=True)
if not (dest/f'{name}.json').exists():raise SystemExit(f'No fresh engine report; exit={proc.returncode}; see {name}.log')
r=json.loads((dest/f'{name}.json').read_text('utf8'))
errors=[e for ph in r['phases'].values() for e in ph.get('errors',[]) if not any(n in e['message'] for n in ('[ShaderError]','Could not initialize audio output'))]
evidence=re.findall(rb'\[Review3QA\] (\{[^\r\n]+\})',log)
report={'result':r['result'],'exit':proc.returncode,'frames':r['frames_completed'],'tests':r.get('test_assertions'),
    'errors':errors,'missing_resources':r.get('missing_resources'),'screenshot':(dest/f'{name}.png').exists(),
    'engine_frame_samples_ms':[s['frame_time_ms'] for s in r.get('state_snapshots',[]) if s.get('frame',0)>10],
    'snapshot':json.loads(evidence[-1]) if evidence else None,
    'source_sha256':{str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in (ROOT/'scripts/defense').rglob('*.lua')}}
(dest/f'{name}-summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:report[k] for k in report if k!='source_sha256'},ensure_ascii=False))
raise SystemExit(1 if proc.returncode!=0 or errors or r.get('missing_resources') or r.get('test_result')!='PASSED' or not report['screenshot'] or not report['snapshot'] or r['result']!='PASS' else 0)
