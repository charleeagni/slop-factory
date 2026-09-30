#!/usr/bin/env python3
# Optional macOS release-app smoke check. Requires Python 3 and Xcode.
# Native inspection checks decoded fixture pixels, animation, and metadata.
import json, os, pathlib, subprocess, time
repo=pathlib.Path(__file__).resolve().parent.parent
root=repo/'.build/recorder-smoke'/('data-'+str(time.time_ns()))
root.mkdir(parents=True,exist_ok=True)
cli=root/'fixture-claude'
fixture=repo/'Tests/RecorderIntegration/Fixtures/animated/index.html'
cli.write_text('#!/bin/bash\nif [[ "$2" == "ok" ]]; then\n  echo \'{"type":"result","is_error":false,"modelUsage":{"claude-recorder-fixture":{}}}\'\nelse\n  /bin/cp '+repr(str(fixture))+' index.html\nfi\n')
cli.chmod(0o755)
(root/'cli-paths.json').write_text(json.dumps({'claude':str(cli),'path':'/usr/bin:/bin'}))
(root/'seen.json').write_text(json.dumps({'seenModels':[], 'lastCheck':0, 'initializedSources':['claude-opus','claude-sonnet','claude-haiku']}))
# This recording fixture has no sharing destination or grant. A declined
# fixture choice keeps the first-launch disclosure from blocking the scheduler.
choice=root/'x-username-sharing-v1.json'
choice.write_text(json.dumps({'format':1, 'choice':'declined',
                             'version':'x-username-feedback-v1', 'time':0, 'withdrawals':[]}))
choice.chmod(0o600)
app=repo/'.build/recorder-smoke/Slop Factory.app/Contents/MacOS/SlopFactory'
# Keep this recording-only smoke run offline. The real scheduler, generation
# process boundary, recorder and release binary run unchanged. No X upload.
command=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(app),'--app-data-folder',str(root),'-draftOnly','YES','-repositoryURL','https://github.com/example/slop-factory']
env=dict(os.environ, SLOP_FACTORY_SUPABASE_URL='', SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY='')
with (root/'app.log').open('w') as log:
    process=subprocess.Popen(command,env=env,stdout=log,stderr=log)
    try:
        until=time.monotonic()+120
        while time.monotonic()<until:
            if process.poll() is not None: raise RuntimeError('app exited '+str(process.returncode))
            movies=list(root.glob('runs/*/demo.mp4'))
            # SlopRun calls the poster only after the synchronous Recorder has
            # returned, including finishWriting. Its post.log is a completion
            # signal even when the offline X compose load subsequently fails.
            if movies and movies[0].with_name('post.log').exists():
                movie=movies[0]
                break
            time.sleep(.25)
        else: raise RuntimeError('no complete movie within 120s')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill();process.wait()
subprocess.run([str(repo/'Scripts/test-recorder.sh'),str(root/'inspection'),
                'inspect-animated',str(movie)],check=True)
print('PASS built app automatic recording:',movie,flush=True)
