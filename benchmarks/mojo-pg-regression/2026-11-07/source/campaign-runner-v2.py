import os,sys,json,time,subprocess,pathlib
run=pathlib.Path('/private/tmp/gpforum-perf-investigation-location').read_text().strip()
run=pathlib.Path(run)
label=sys.argv[1]
source=run/sys.argv[2]
env={k:v for k,v in os.environ.items() if not k.startswith('GPFORUM_') and k not in {'PGHOST','PGPORT','PGUSER','PGPASSWORD','PGDATABASE','PGSERVICE','MOJO_MODE','MOJO_REACTOR','LIBEV_FLAGS','NYTPROF','PERL5OPT'}}
env['PATH']='/opt/homebrew/opt/postgresql@18/bin:'+env['PATH']
def peers(own):
 rows=[]
 for line in subprocess.check_output(['ps','-Ao','pid,ppid,args'],text=True).splitlines()[1:]:
  p=line.strip().split(None,2)
  if len(p)==3: rows.append((int(p[0]),int(p[1]),p[2]))
 ours={own}
 for _ in range(15): ours.update(pid for pid,parent,_ in rows if parent in ours)
 return [{'pid':pid,'command':cmd[:350]} for pid,parent,cmd in rows if pid not in ours and any(x in cmd for x in ['bin/prove ',' -S prove ','/perl t/integration/','node --test ','/script/perlcritic ','/script/test','script/fresh-checkout-check','script/benchmark-http-complete','script/performance-http','script/bench-socket','script/bench-render','cpanm ','cpm install','script/perlcritic']) and not cmd.startswith(('/bin/zsh -c','/bin/zsh -lc','/bin/sh -c'))]
history=[]
for _ in range(240):
 competing=peers(os.getpid())
 if not competing: break
 history.append({'time':time.time(),'phase':'waiting','peers':competing})
 (run/(label+'-monitor.json')).write_text(json.dumps(history,indent=2))
 time.sleep(2)
else: sys.exit('competing verification still running')
command=['script/gpforum-carton','exec','script/benchmark-http-complete','--output',str(run/label),'--workers','2','--iterations','40','--warmup','10','--duration','4','--repetitions','2','--concurrency','1,10,32,100','--deadline','600']
for scenario in (sys.argv[3].split(',') if len(sys.argv)>3 else ['member.thread']):command+=['--scenario',scenario]
with (run/(label+'.log')).open('w') as log:
 child=subprocess.Popen(command,cwd=source,env=env,stdout=log,stderr=subprocess.STDOUT)
 while child.poll() is None:
  history.append({'time':time.time(),'phase':'running','peers':peers(os.getpid())})
  time.sleep(.5)
 code=child.returncode
(run/(label+'-monitor.json')).write_text(json.dumps(history,indent=2))
record={'command':command,'source':str(source),'exit':code,'contaminated':any(x['peers'] for x in history if x['phase']=='running')}
(run/(label+'-run.json')).write_text(json.dumps(record,indent=2))
print(json.dumps(record),flush=True)
sys.exit(code)
