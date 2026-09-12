"""Small, complete examples of the retained Windows consumer evidence shapes.

Paths/PIDs/media bytes are synthetic; assertions exercise the production exporter.
The schema follows the successful Store qualification run 34669262949.
"""
import json
import ntpath
from pathlib import Path

from source_publication import digest


def workflow_fixture(source, commit, runtime, payload, full_name):
    helpers = {}
    for name in ('qualify-msix-install.ps1', 'workflow-functions.ps1', 'workflowUi.mjs'):
        data = (Path(__file__).parent / name).read_bytes()
        target = source / 'script/msix' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        helpers[name] = digest(data)['sha256']
    fixture = r'D:\a\_temp\.cutquay-install-fixture\workflow-media\source.mp4'
    output = fixture.replace('source.mp4', 'source-00.00.02.000-00.00.05.000.mp4')
    package_root = 'C:\\Program Files\\WindowsApps\\' + full_name
    work_root = ntpath.dirname(ntpath.dirname(fixture))
    input_hash = {'bytes': 456, 'sha256': '4'*64}
    output_hash = {'bytes': 123, 'sha256': '3'*64}
    recipe = {'version': 1, 'id': 'saved-fixture', 'name': 'Original CI three-second trim',
        'exportMode': 'separate', 'outFormat': 'mp4', 'keyframeCut': True, 'enableOverwriteOutput': False}
    report = {'version': 1, 'operation': 'cut', 'status': 'succeeded', 'sources': [fixture], 'recipe': recipe,
        'segments': [{'requestedStart': 2, 'requestedEnd': 5, 'keyframeCut': True}],
        'effective': {'mode': 'lossless', 'ffmpegVersion': runtime['media']['version'],
            'ffmpegConfiguration': runtime['media']['configuration']},
        'outputs': [{'path': output, 'status': 'created', 'sizeBytes': output_hash['bytes']}],
        'commands': [['-ss', '2.000000', '-i', fixture, '-t', '3.000000', '-f', 'mp4', output]]}
    probe = {'streams': [{'codec_type': 'video', 'codec_name': 'h264', 'width': 160, 'height': 90},
        {'codec_type': 'audio', 'codec_name': 'aac'}],
        'format': {'duration': '3.03', 'filename': output, 'size': str(output_hash['bytes'])}}
    media = {'decoded': True, 'input': input_hash, 'output': output_hash, 'probe': probe}
    records = {'workflow-export/consumer-export-report.json': report, 'workflow-export/saved-recipe.json': recipe,
        'workflow-export/trim-entered.json': {'inputs': [
            {'title': "Manually input current segment's start time", 'value': '00:00:02.000', 'disabled': False},
            {'title': "Manually input current segment's end time", 'value': '00:00:05.000', 'disabled': False}]},
        'workflow-reopen/persisted-recipe-reapplied.json': {'selects': [
            {'id': 'export-recipe', 'value': recipe['id']}, {'title': 'Output container format:', 'value': 'mp4'}]}}
    workflow = {'source_commit': commit, 'passed': True, 'input': input_hash, 'media': media}
    for phase, pid in [('export', 111), ('reopen', 222)]:
        imported = fixture if phase == 'export' else output
        ui = {'schemaVersion': 1, 'phase': phase, 'sourceCommit': commit, 'packageFullName': full_name,
            'brokerProcessId': pid, 'automation': 'unmodified consumer renderer; loopback CDP input',
            'passed': True, 'rendererExceptions': [], 'output': output, 'outputHash': output_hash,
            'steps': [{'action': 'file-drop', 'path': imported}]}
        if phase == 'export':
            ui.update(recipe=recipe, inputHash=input_hash, reportHash=digest(json_bytes(report)))
        else:
            ui.update(persistedRecipeApplied=True, reopenedDuration=3.03)
        workflow[phase+'_ui'] = ui
        records[f'workflow-{phase}/{phase}-ui-result.json'] = ui
        records[f'workflow-{phase}/driver.json'] = {'driver_sha256': helpers['workflowUi.mjs'],
            'node_sha256': '5'*64, 'input_sha256': str(pid)[0]*64, 'exit_code': 0,
            'broker_process_id': pid, 'broker_start_ticks': 600000000000000000+pid,
            'package_full_name': full_name, 'loopback_listener_verified': True,
            'arguments': ['--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1',
                '--user-data-dir='+work_root+'\\workflow-profile-'+phase, '--config-dir='+work_root+'\\workflow-config',
                '--disable-networking']}
        records[f'workflow-{phase}/loaded-modules.json'] = [{'process_id': pid,
            'path': package_root+'\\CutQuay.exe', 'origin': 'package', 'relative_path': 'CutQuay.exe',
            'sha256': payload['CutQuay.exe']['sha256']}]
    for mode, key, pid in [('generate', 'generation_worker', 333), ('verify', 'verification_worker', 444)]:
        worker = {'process_id': pid, 'start_ticks': 600000000000000000+pid,
            'executable': r'C:\Program Files\PowerShell\7\pwsh.EXE', 'package_full_name': full_name,
            'input_sha256': str(pid)[0]*64, 'helper_sha256': helpers['qualify-msix-install.ps1'],
            'workflow_helper_sha256': helpers['workflow-functions.ps1'], 'clean_exit_verified': True, 'exit_code': 0}
        workflow[key] = worker
        common = {'nonce': str(pid)[0]*32, 'input_sha256': worker['input_sha256'], 'package_full_name': full_name}
        records[f'{mode}-media/media-worker-ready.json'] = dict(common, process_id=pid, start_ticks=worker['start_ticks'])
        records[f'{mode}-media/media-worker-authorized.json'] = {'nonce': common['nonce'], 'process_id': pid, 'start_ticks': worker['start_ticks']}
        records[f'{mode}-media/media-worker-result.json'] = dict(common, primary_error=None, cleanup_errors=[],
            installed_media=[{'generated': True, 'input': input_hash} if mode == 'generate' else media])
    generate = ['-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
        'testsrc2=size=160x90:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
        '-t', '8', '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'libx264', '-preset', 'ultrafast',
        '-pix_fmt', 'yuv420p', '-g', '25', '-keyint_min', '25', '-sc_threshold', '0', '-c:a', 'aac', '-b:a', '96k', fixture]
    for name, exe, args in [('generate-media/generate-native.json', 'ffmpeg', generate),
        ('verify-media/probe-output-native.json', 'ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', output]),
        ('verify-media/decode-output-native.json', 'ffmpeg', ['-hide_banner', '-loglevel', 'error', '-nostdin', '-xerror', '-i', output, '-map', '0:v:0', '-map', '0:a:0', '-f', 'null', '-'])]:
        relative = f'resources/{exe}.exe'
        path = package_root+'\\'+relative.replace('/', '\\')
        observed = lambda value: {'status': 'observed', 'value': value, 'error': None, 'process_exit_observed': False}
        records[name] = {'program': relative, 'executable_sha256': payload[relative]['sha256'],
            'launch_executable_path': path, 'process_image_path': path, 'arguments': args, 'package_full_name': full_name,
            'process_identity': {'process_id': 555, 'handle_origin': 'successful Process.Start; original handle retained',
                'package': observed(full_name), 'image': observed(path)},
            'expected_parent_package_context': full_name, 'exit_code': 0,
            'stdout': json.dumps(probe) if exe == 'ffprobe' else '', 'stderr': ''}
    return workflow, records


def json_bytes(value):
    return (json.dumps(value, indent=2)+'\n').encode()
