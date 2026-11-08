#!/usr/bin/env python3
"""Mock executables only: never launches a real Unity Editor."""
import json, os, plistlib, shutil, socket, subprocess, sys, tempfile, unittest, time, unicodedata
from contextlib import ExitStack
from pathlib import Path
SCRIPT=Path(__file__).resolve().parents[1]/'scripts/setup/open-unity-editor.sh'

@unittest.skipUnless(sys.platform=='darwin','macOS launcher; Windows not_run')
class OpenUnityEditorTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.project=self.root/'nested folder/project with spaces';(self.project/'ProjectSettings').mkdir(parents=True)
        (self.project/'ProjectSettings/ProjectVersion.txt').write_text('m_EditorVersion: 6000.3.15f1\n')
        self.app=self.root/'exact editor/Unity.app';(self.app/'Contents/MacOS').mkdir(parents=True)
        (self.app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'Unity version 6000.3.15f1','CFBundleVersion':'6000.3.15f1','CFBundleExecutable':'Unity'}))
        (self.app/'Contents/MacOS/Unity').write_text('fixture');(self.app/'Contents/MacOS/Unity').chmod(0o755)
        self.bin=self.root/'bin';self.bin.mkdir()
        self.mock('python3','import os,sys\nos.execv(sys.executable,[sys.executable,*sys.argv[1:]])')
        self.env={**os.environ,'HOME':str(self.root/'home'),'PATH':str(self.bin),'LAUNCH_LOG':str(self.root/'launch.jsonl')}
        self.mock('unity','import os,sys,json\nwith open(os.environ["LAUNCH_LOG"],"a") as f:f.write(json.dumps(["unity",*sys.argv[1:]])+"\\n")\nsys.exit(int(os.environ.get("CLI_EXIT","0")))')
        self.mock('open','import os,sys,json\nwith open(os.environ["LAUNCH_LOG"],"a") as f:f.write(json.dumps(["open",*sys.argv[1:]])+"\\n")\nsys.exit(int(os.environ.get("APP_EXIT","0")))')
        self.mock('ps','import os\nprint(os.environ.get("PS_OUTPUT",""))')
    def mock(self,name,body):
        if name not in ('unity','open','ps','python3') or self.bin.is_symlink() or self.bin.resolve().parent != self.root.resolve():
            raise ValueError('mock executable must be a direct fixture bin entry')
        p=self.bin/name
        p.unlink(missing_ok=True)  # Remove the directory entry, never write through a runtime symlink.
        with p.open('x') as stream:stream.write('#!'+sys.executable+'\n'+body+'\n')
        p.chmod(0o755);return p
    def test_mock_replaces_links_without_changing_runtime_target(self):
        target=self.root/'fake-runtime';target.write_bytes(b'unchanged runtime bytes')
        entry=self.bin/'python3'
        for kind in ('symlink','hardlink'):
            with self.subTest(kind=kind):
                entry.unlink(missing_ok=True)
                if kind=='symlink':entry.symlink_to(target)
                else:os.link(target,entry)
                self.mock('python3','pass')
                self.assertEqual(target.read_bytes(),b'unchanged runtime bytes')
                self.assertFalse(entry.is_symlink());self.assertFalse(entry.samefile(target))

    def test_python_wrapper_preserves_arguments_and_stdin(self):
        self.assertFalse((self.bin/'python3').is_symlink())
        r=subprocess.run([str(self.bin/'python3'),'-c','import json,sys;print(json.dumps([sys.argv[1:],sys.stdin.read()]))','arg with spaces','-x'],input='stdin bytes',capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(json.loads(r.stdout),[['arg with spaces','-x'],'stdin bytes'])

    def test_invalid_plist_fails_cleanly_without_launch(self):
        for data in (b'<?xml version="1.0"?><plist><dict>',
                     b'<?xml version="1.0" encoding="x-bogus"?><plist version="1.0"><dict/></plist>',
                     plistlib.dumps(['unexpected'])):
            with self.subTest(data=data):
                (self.app/'Contents/Info.plist').write_bytes(data)
                r=self.run_launcher('--skip-cli')
                self.assertEqual(r.returncode,4,r.stderr)
                self.assertIn('Info.plist',r.stderr);self.assertNotIn('Traceback',r.stderr)
                self.assertEqual(self.calls(),[])

    def test_malformed_plist_date_fails_cleanly_without_launch(self):
        (self.app/'Contents/Info.plist').write_bytes(b'<?xml version="1.0"?><plist version="1.0"><dict><key>date</key><date>garbage</date></dict></plist>')
        r=self.run_launcher('--skip-cli')
        self.assertEqual(r.returncode,4,r.stderr);self.assertIn('Info.plist',r.stderr)
        self.assertNotIn('Traceback',r.stderr);self.assertEqual(self.calls(),[])

    def test_nonregular_plist_rejected_without_blocking(self):
        p=self.app/'Contents/Info.plist';p.unlink();fifo=self.root/'fixture.fifo';os.mkfifo(fifo)
        for kind in ('fifo','linked_fifo','directory','linked_socket','linked_devzero'):
            with self.subTest(kind=kind), ExitStack() as resources:
                try:
                    if kind=='fifo':os.mkfifo(p)
                    elif kind=='linked_fifo':p.symlink_to(fifo)
                    elif kind=='directory':p.mkdir()
                    elif kind=='linked_socket':
                        socket_dir=Path(resources.enter_context(tempfile.TemporaryDirectory(dir='/tmp',prefix='h-')))
                        listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
                        resources.callback(listener.close)
                        socket_path=socket_dir/'s';listener.bind(str(socket_path));p.symlink_to(socket_path)
                    else:
                        self.assertTrue(Path('/dev/zero').exists())
                        p.symlink_to('/dev/zero')
                    r=subprocess.run(['/bin/bash',str(SCRIPT),'--project-root',str(self.project),'--unity-app',str(self.app),'--skip-cli'],env=self.env,capture_output=True,text=True,timeout=2)
                    self.assertEqual(r.returncode,4,r.stderr);self.assertIn('Info.plist',r.stderr)
                    self.assertNotIn('Traceback',r.stderr);self.assertEqual(self.calls(),[])
                finally:
                    if p.is_dir() and not p.is_symlink():p.rmdir()
                    else:p.unlink(missing_ok=True)

    def run_launcher(self,*args):
        return subprocess.run(['/bin/bash',str(SCRIPT),'--project-root',str(self.project),'--unity-app',str(self.app),*args],env=self.env,capture_output=True,text=True)
    def calls(self):
        p=self.root/'launch.jsonl';return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
    def test_cli_success_never_opens_app(self):
        r=self.run_launcher();self.assertEqual(r.returncode,0,r.stderr);self.assertIn('launched_via=cli',r.stdout);self.assertIn('identity=unverified',r.stdout)
        self.assertEqual(self.calls(),[['unity','open',str(self.project.resolve()),'--editor-version','6000.3.15f1']])
    def test_cli_failure_opens_exact_app_once(self):
        self.env['CLI_EXIT']='1';r=self.run_launcher();self.assertEqual(r.returncode,0,r.stderr);self.assertIn('launched_via=app',r.stdout)
        self.assertEqual(self.calls()[1:], [['open','-gna',str(self.app.resolve()),'--args','-projectPath',str(self.project.resolve())]])
    def test_missing_cli_uses_app_and_home_cli_is_supported(self):
        executable=self.bin/'unity';home=Path(self.env['HOME'])/'.unity/bin';home.mkdir(parents=True);shutil.move(executable,home/'unity')
        self.assertEqual(self.run_launcher().returncode,0);self.assertEqual(self.calls()[0][0],'unity')
        (home/'unity').unlink();self.assertEqual(self.run_launcher().returncode,0);self.assertEqual(self.calls()[-1][0],'open')
    def test_missing_or_mismatched_app_is_rejected(self):
        self.env['CLI_EXIT']='1';(self.app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'6000.3.14f1'}))
        self.assertNotEqual(self.run_launcher().returncode,0);shutil.rmtree(self.app);self.assertNotEqual(self.run_launcher().returncode,0)
        self.assertFalse(any(c[0]=='open' for c in self.calls()))
    def test_lock_and_existing_process_reject_without_launch(self):
        lock=self.project/'Temp/UnityLockfile';lock.parent.mkdir();lock.touch()
        self.assertNotEqual(self.run_launcher().returncode,0);self.assertTrue(lock.exists());self.assertEqual(self.calls(),[])
        lock.unlink();self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' -projectPath '+str(self.project.resolve())+' -logFile /tmp/log'
        self.assertNotEqual(self.run_launcher().returncode,0);self.assertEqual(self.calls(),[])
    def test_cli_partial_launch_lock_prevents_native_retry(self):
        self.mock('unity','import pathlib,sys\np=pathlib.Path(sys.argv[2])/"Temp/UnityLockfile"\np.parent.mkdir(exist_ok=True);p.touch();sys.exit(1)')
        self.assertNotEqual(self.run_launcher().returncode,0);self.assertEqual(self.calls(),[])
    def test_project_process_path_aliases(self):
        alias=self.root/'alias';alias.symlink_to(self.project,target_is_directory=True)
        for flag,path in [('-projectpath',str(self.project)),('-PROJECTPATH',str(self.project)+'/'),('-projectPath',str(alias))]:
            with self.subTest(flag=flag,path=path):
                self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' '+flag+' '+path+' -logFile /tmp/log'
                self.assertNotEqual(self.run_launcher().returncode,0)
                self.assertEqual(self.calls(),[])
        korean=self.project.with_name('한글 프로젝트');self.project.rename(korean);self.project=korean
        self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' -projectpath "'+unicodedata.normalize('NFD',str(korean))+'/"'
        self.assertNotEqual(self.run_launcher().returncode,0);self.assertEqual(self.calls(),[])

    def test_cli_timeout_does_not_retry_uncertain_launch(self):
        self.mock('unity','import time\ntime.sleep(10)')
        start=time.monotonic();r=self.run_launcher('--cli-timeout','0.1')
        self.assertLess(time.monotonic()-start,3);self.assertNotEqual(r.returncode,0)
        self.assertIn('timed out',r.stderr);self.assertEqual(self.calls(),[])

    def test_cli_stdin_is_closed(self):
        self.mock('unity','import sys\nsys.exit(0 if sys.stdin.read()=="" else 9)')
        r=self.run_launcher();self.assertEqual(r.returncode,0,r.stderr);self.assertIn('launched_via=cli',r.stdout)

    def test_skip_cli_avoids_retry(self):
        r=self.run_launcher('--skip-cli');self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual([c[0] for c in self.calls()],['open'])

    def test_hub_secondary_install_path_discovery(self):
        hub=Path(self.env['HOME'])/'Library/Application Support/UnityHub';hub.mkdir(parents=True)
        install=self.root/'custom Hub editor';target=install/'6000.3.15f1/Unity.app';target.parent.mkdir(parents=True)
        shutil.move(self.app,target);(hub/'secondaryInstallPath.json').write_text(json.dumps(str(install)))
        r=subprocess.run(['/bin/bash',str(SCRIPT),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.calls()[0][2],str(target.resolve()))

    def test_option_like_project_name_still_blocks_duplicate(self):
        renamed=self.project.with_name('project -game');self.project.rename(renamed);self.project=renamed
        for path in (str(renamed), '"'+str(renamed)+'"'):
            with self.subTest(path=path):
                self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' -projectPath '+path+' -logFile /tmp/log'
                self.assertNotEqual(self.run_launcher().returncode,0);self.assertEqual(self.calls(),[])

    def test_trailing_space_project_process_blocks_duplicate(self):
        renamed=self.project.with_name('trail  ');self.project.rename(renamed);self.project=renamed
        for quoted in (False,True):
            for suffix in ('',' -logFile /tmp/log'):
                with self.subTest(quoted=quoted,suffix=suffix):
                    (self.root/'launch.jsonl').unlink(missing_ok=True)
                    path='"'+str(renamed)+'"' if quoted else str(renamed)
                    self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' -projectPath '+path+suffix
                    r=self.run_launcher('--skip-cli');self.assertNotEqual(r.returncode,0,r.stdout);self.assertEqual(self.calls(),[])

    def test_malformed_hub_config_recommends_explicit_app(self):
        hub=Path(self.env['HOME'])/'Library/Application Support/UnityHub';hub.mkdir(parents=True)
        (hub/'secondaryInstallPath.json').write_text('{broken')
        r=subprocess.run(['/bin/bash',str(SCRIPT),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
        self.assertEqual(r.returncode,4);self.assertIn('--unity-app',r.stderr);self.assertEqual(self.calls(),[])

    def test_unreadable_hub_config_recommends_explicit_app(self):
        hub=Path(self.env['HOME'])/'Library/Application Support/UnityHub';hub.mkdir(parents=True)
        config=hub/'secondaryInstallPath.json'
        for data in (b'\xff\xfe\x80', '"/editor"'.encode('utf-16')):
            with self.subTest(data=data):
                config.write_bytes(data)
                r=subprocess.run(['/bin/bash',str(SCRIPT),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
                self.assertEqual(r.returncode,4);self.assertIn('--unity-app',r.stderr);self.assertNotIn('Traceback',r.stderr);self.assertEqual(self.calls(),[])
        config.unlink();config.mkdir()
        r=subprocess.run(['/bin/bash',str(SCRIPT),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
        self.assertEqual(r.returncode,4);self.assertIn('--unity-app',r.stderr);self.assertEqual(self.calls(),[])

    def test_broken_hub_links_and_deep_json_fail_without_launch(self):
        hub=Path(self.env['HOME'])/'Library/Application Support/UnityHub';hub.mkdir(parents=True)
        config=hub/'secondaryInstallPath.json'
        # Temp default installation makes accidental fallback observable without a real app.
        install=self.root/'default Hub';target=install/'6000.3.15f1/Unity.app';target.parent.mkdir(parents=True);shutil.copytree(self.app,target)
        launcher=self.root/'launcher.sh';source=SCRIPT.read_text();literal="Path('/Applications/Unity/Hub/Editor')"
        self.assertEqual(source.count(literal),1);launcher.write_text(source.replace(literal,'Path('+repr(str(install))+')'))
        r=subprocess.run(['/bin/bash',str(launcher),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr);self.assertEqual([c[0] for c in self.calls()],['open'])
        (self.root/'launch.jsonl').unlink()
        for kind in ('dangling','loop','nested'):
            with self.subTest(kind=kind):
                if kind=='dangling':config.symlink_to(hub/'missing.json')
                elif kind=='loop':config.symlink_to(config.name)
                else:config.write_text('['*100000)
                try:
                    r=subprocess.run(['/bin/bash',str(launcher),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
                    self.assertEqual(r.returncode,4);self.assertIn('--unity-app',r.stderr);self.assertNotIn('Traceback',r.stderr);self.assertEqual(self.calls(),[])
                    # An explicit app remains authoritative even with invalid Hub state.
                    r=self.run_launcher('--skip-cli');self.assertEqual(r.returncode,0,r.stderr)
                    self.assertEqual([c[0] for c in self.calls()],['open'])
                finally:
                    config.unlink();(self.root/'launch.jsonl').unlink(missing_ok=True)

    def test_python39_resolve_loop_runtime_error_is_handled(self):
        # Python 3.9 raises RuntimeError where newer pathlib may raise OSError.
        # Inject that exception through the actual embedded helper entry point.
        loop=self.root/'loop';loop.symlink_to(loop.name)
        self.env['FAIL_RESOLVE_PATH']=str(loop)
        self.mock('python3', 'import os,pathlib,sys\ncode=sys.stdin.read();sys.argv=sys.argv[1:]\noriginal=pathlib.Path.resolve\ndef resolve(path,*args,**kwargs):\n if str(path)==os.environ["FAIL_RESOLVE_PATH"]:raise RuntimeError("Symlink loop from fixture")\n return original(path,*args,**kwargs)\npathlib.Path.resolve=resolve\nexec(compile(code,"<helper>","exec"))')
        for location in ('project','process','app'):
            with self.subTest(location=location):
                self.env.pop('PS_OUTPUT',None)
                extra=['--skip-cli']
                if location=='project':extra+=['--project-root',str(loop)]
                elif location=='app':extra+=['--unity-app',str(loop)]
                else:self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' -projectPath '+str(loop)
                r=self.run_launcher(*extra)
                self.assertEqual(r.returncode,4);self.assertIn('Symlink loop',r.stderr);self.assertNotIn('Traceback',r.stderr);self.assertEqual(self.calls(),[])

    def test_ambiguous_flattened_project_path_is_not_claimed_exact(self):
        renamed=self.project.with_name('my');self.project.rename(renamed);self.project=renamed
        other=renamed.with_name('my -game');other.mkdir()
        self.env['PS_OUTPUT']=str(self.app/'Contents/MacOS/Unity')+' -projectPath '+str(other)
        r=self.run_launcher('--skip-cli');self.assertEqual(r.returncode,4);self.assertEqual(self.calls(),[])
        self.assertIn('ambiguous',r.stderr);self.assertNotIn('already targets this project',r.stderr)

    def test_empty_secondary_config_uses_default_hub_location(self):
        # Replace only the system installation root in a fixture copy; never
        # create /Applications entries or inspect/launch a real installed app.
        install=self.root/'default Hub';target=install/'6000.3.15f1/Unity.app';target.parent.mkdir(parents=True);shutil.move(self.app,target)
        launcher=self.root/'launcher.sh';source=SCRIPT.read_text();literal="Path('/Applications/Unity/Hub/Editor')"
        self.assertEqual(source.count(literal),1);launcher.write_text(source.replace(literal,'Path('+repr(str(install))+')'))
        hub=Path(self.env['HOME'])/'Library/Application Support/UnityHub';hub.mkdir(parents=True)
        for value in ('', '   \n', '""'):
            with self.subTest(value=value):
                (hub/'secondaryInstallPath.json').write_text(value)
                r=subprocess.run(['/bin/bash',str(launcher),'--project-root',str(self.project),'--skip-cli'],env=self.env,capture_output=True,text=True)
                self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.calls()[-1][2],str(target.resolve()))

    def test_missing_project_version_and_native_failure(self):
        self.env.update(CLI_EXIT='1',APP_EXIT='1');self.assertNotEqual(self.run_launcher().returncode,0);self.assertEqual(sum(c[0]=='open' for c in self.calls()),1)
        (self.project/'ProjectSettings/ProjectVersion.txt').unlink();self.assertNotEqual(self.run_launcher().returncode,0)

if __name__=='__main__':unittest.main()
