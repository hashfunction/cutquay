"""Cross-check retained consumer evidence before exporting an unsigned Store MSIX.

These checks mirror the existing installed workflow contract. They do not replace
Windows execution, grant process ownership, or turn a summary's passed flag into
proof of an operation whose retained evidence is missing.
"""
import json
import math
import ntpath
from pathlib import PureWindowsPath
import re

from source_publication import digest, require


def positive(value):
    return type(value) is int and value > 0


def sha256(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value)


def file_digest(value):
    require(set(value) == {'bytes', 'sha256'} and positive(value['bytes']) and sha256(value['sha256']),
        'Invalid consumer file digest')


def windows_path(value):
    require(isinstance(value, str) and PureWindowsPath(value).is_absolute()
        and re.match(r'^[A-Za-z]:[\\/]', value) and '..' not in PureWindowsPath(value).parts,
        'Invalid absolute Windows evidence path')
    return ntpath.normcase(ntpath.normpath(value))


def validate_worker(worker, mode, result_media, package, load, helpers):
    require(worker.get('package_full_name') == package and worker.get('clean_exit_verified') is True
        and type(worker.get('exit_code')) is int and worker['exit_code'] == 0
        and positive(worker.get('process_id')) and positive(worker.get('start_ticks')),
        'Installed worker identity/exit did not pass')
    require(sha256(worker.get('input_sha256')) and worker.get('helper_sha256') == helpers['qualify-msix-install.ps1']
        and worker.get('workflow_helper_sha256') == helpers['workflow-functions.ps1'],
        'Installed worker inputs/helpers differ from current source')
    require(PureWindowsPath(windows_path(worker['executable'])).name == 'pwsh.exe', 'Invalid observed worker executable')
    ready = load(f'{mode}-media/media-worker-ready.json')
    authorized = load(f'{mode}-media/media-worker-authorized.json')
    result = load(f'{mode}-media/media-worker-result.json')
    require(isinstance(ready.get('nonce'), str) and re.fullmatch('[0-9a-f]{32}', ready['nonce']), 'Invalid worker nonce')
    require(authorized == {key: ready[key] for key in ('nonce', 'process_id', 'start_ticks')}
        and all(ready.get(key) == worker[key] for key in ('process_id', 'start_ticks', 'input_sha256', 'package_full_name')),
        'Worker authorization differs from observed process/input')
    require(all(result.get(key) == ready[key] for key in ('nonce', 'input_sha256', 'package_full_name'))
        and result.get('primary_error') is None and result.get('cleanup_errors') == []
        and result.get('installed_media') == [result_media], 'Worker result is incomplete or differs from consumer media')


def validate_native(row, program, arguments, payload, package):
    relative = f'resources/{program}.exe'
    launch = windows_path(row['launch_executable_path'])
    root = PureWindowsPath(launch).parent.parent
    require(root.name == package.lower() and root.parent.name == 'windowsapps'
        and launch == windows_path(str(root / relative)), 'Media launch is outside exact installed package')
    require(row.get('program') == relative and row.get('executable_sha256') == payload[relative]['sha256']
        and row.get('arguments') == arguments and type(row.get('exit_code')) is int and row['exit_code'] == 0
        and row.get('expected_parent_package_context') == package, 'Native media command/runtime/exit differs')
    identity = row['process_identity']
    require(positive(identity.get('process_id'))
        and identity.get('handle_origin') == 'successful Process.Start; original handle retained',
        'Native media lacks retained process identity')
    for key, expected, field in [('image', launch, 'process_image_path'), ('package', package, 'package_full_name')]:
        observation = identity[key]
        require(row.get(field) == observation.get('value'), 'Native media observation summary differs')
        if observation.get('status') == 'observed':
            value = windows_path(observation['value']) if key == 'image' else observation['value']
            require(value == expected and observation.get('error') is None and observation.get('process_exit_observed') is False,
                'Native media observed a different process identity')
        else:
            # Short-lived processes may exit before an original-handle query.
            # Preserve that explicitly recorded case; a returned mismatch never qualifies.
            error = observation.get('error')
            require(observation.get('status') == 'unavailable_after_observed_exit'
                and observation.get('value') is None and observation.get('process_exit_observed') is True
                and isinstance(error, dict) and isinstance(error.get('type'), str) and bool(error['type'])
                and isinstance(error.get('message'), str) and bool(error['message']),
                'Native media identity is incomplete without observed exit')
    return root


def validate_workflow(workflow, commit, package, payload, runtime, load, raw, helpers):
    require(workflow.get('source_commit') == commit and workflow.get('passed') is True,
        'Consumer workflow did not pass this source')
    export, reopen, media = workflow['export_ui'], workflow['reopen_ui'], workflow['media']
    file_digest(workflow['input']);file_digest(export['outputHash'])
    require(workflow['input'] == export['inputHash'] == media['input'], 'Consumer input hashes differ')
    require(export['outputHash'] == reopen['outputHash'] == media['output'], 'Export/decode/reopen output hashes differ')
    require(media.get('decoded') is True and reopen.get('persistedRecipeApplied') is True,
        'Decode or persisted recipe reapplication did not pass')
    output = export['output']
    require(output == reopen['output'], 'Reopened output path differs')
    report_name = 'workflow-export/consumer-export-report.json'
    report, recipe = load(report_name), load('workflow-export/saved-recipe.json')
    require(export['reportHash'] == digest(raw(report_name)), 'Consumer report bytes differ from UI observation')
    require(recipe == export['recipe'] == report['recipe'] and type(recipe.get('version')) is int and recipe['version'] == 1
        and recipe.get('name') == 'Original CI three-second trim' and isinstance(recipe.get('id'), str)
        and recipe['id'] not in ('', 'current') and recipe.get('outFormat') == 'mp4'
        and recipe.get('exportMode') == 'separate' and recipe.get('keyframeCut') is True
        and recipe.get('enableOverwriteOutput') is False, 'Saved/exported recipe differs from requested operation')
    # FFmpeg appends the configured --extra-version to its upstream version.
    # Derive the exact observed version from the already pinned configuration.
    extra = re.findall(r'(?:^| )--extra-version=([A-Za-z0-9._-]+)(?= |$)', runtime['media']['configuration'])
    require(len(extra) <= 1, 'Ambiguous pinned FFmpeg extra-version')
    version = runtime['media']['version'] + ('-' + extra[0] if extra else '')
    require(type(report.get('version')) is int and report['version'] == 1 and report.get('operation') == 'cut'
        and report.get('status') in ('succeeded', 'succeeded_with_warnings')
        and report['segments'] == [{'requestedStart': 2, 'requestedEnd': 5, 'keyframeCut': True}]
        and report['effective']['mode'] == 'lossless'
        and report['effective']['ffmpegVersion'] == version
        and report['effective']['ffmpegConfiguration'] == runtime['media']['configuration'],
        'Consumer trim/runtime report differs from qualified operation')
    require(isinstance(report['sources'], list) and len(report['sources']) == 1, 'Consumer source is incomplete')
    fixture = report['sources'][0]
    original_path, output_path = windows_path(fixture), windows_path(output)
    require(PureWindowsPath(original_path).name == 'source.mp4' and PureWindowsPath(original_path).parent.name == 'workflow-media'
        and ntpath.dirname(original_path) == ntpath.dirname(output_path) and output_path != original_path
        and ntpath.splitext(output_path)[1] == '.mp4', 'Consumer output is not the separate generated-media destination')
    require(report['outputs'] == [{'path': output, 'status': 'created', 'sizeBytes': export['outputHash']['bytes']}]
        and isinstance(report.get('commands'), list) and bool(report['commands'])
        and all(isinstance(command, list) and bool(command) and all(isinstance(arg, str) for arg in command)
            for command in report['commands']), 'Consumer output/commands are incomplete')
    require(len(report['commands']) == 1, 'Consumer trim did not run one export command')
    command = report['commands'][0]
    for flag, value in [('-ss', '2.000000'), ('-i', fixture), ('-t', '3.000000'), ('-f', 'mp4')]:
        require(command.count(flag) == 1 and command.index(flag)+1 < len(command)
            and command[command.index(flag)+1] == value, 'Consumer command differs from requested input/trim/format')
    probe = media['probe']
    video = [s for s in probe['streams'] if s.get('codec_type') == 'video']
    audio = [s for s in probe['streams'] if s.get('codec_type') == 'audio']
    duration = float(probe['format']['duration'])
    reopened = reopen['reopenedDuration']
    require(len(probe['streams']) == 2 and len(video) == len(audio) == 1 and video[0].get('codec_name') == 'h264'
        and audio[0].get('codec_name') == 'aac' and video[0].get('width') == 160 and video[0].get('height') == 90
        and math.isfinite(duration) and 2.85 <= duration <= 3.15
        and type(reopened) in (int, float) and math.isfinite(reopened) and 2.85 <= reopened <= 3.15
        and abs(reopened-duration) <= 0.1 and probe['format']['filename'] == output
        and probe['format']['size'] == str(export['outputHash']['bytes']), 'Inspected/reopened output is not the requested trim')
    generate_args = ['-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
        'testsrc2=size=160x90:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '8',
        '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-g', '25', '-keyint_min', '25', '-sc_threshold', '0', '-c:a', 'aac', '-b:a', '96k', fixture]
    root = validate_native(load('generate-media/generate-native.json'), 'ffmpeg', generate_args, payload, package)
    probe_record = load('verify-media/probe-output-native.json')
    require(validate_native(probe_record, 'ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', output], payload, package) == root
        and json.loads(probe_record['stdout']) == probe, 'Standalone native probe differs from inspected media')
    require(validate_native(load('verify-media/decode-output-native.json'), 'ffmpeg',
        ['-hide_banner', '-loglevel', 'error', '-nostdin', '-xerror', '-i', output, '-map', '0:v:0', '-map', '0:a:0', '-f', 'null', '-'],
        payload, package) == root, 'Decoder package location differs')
    validate_worker(workflow['generation_worker'], 'generate', {'generated': True, 'input': workflow['input']}, package, load, helpers)
    validate_worker(workflow['verification_worker'], 'verify', media, package, load, helpers)
    generator, verifier = workflow['generation_worker'], workflow['verification_worker']
    require(windows_path(generator['executable']) == windows_path(verifier['executable'])
        and (generator['process_id'], generator['start_ticks']) != (verifier['process_id'], verifier['start_ticks'])
        and generator['input_sha256'] != verifier['input_sha256'], 'Media verification reused an earlier worker invocation')
    brokers = []
    for phase, ui, imported in [('export', export, fixture), ('reopen', reopen, output)]:
        require(load(f'workflow-{phase}/{phase}-ui-result.json') == ui, 'Standalone UI result differs from workflow')
        require(type(ui.get('schemaVersion')) is int and ui['schemaVersion'] == 1 and ui.get('phase') == phase
            and ui.get('sourceCommit') == commit and ui.get('packageFullName') == package and ui.get('passed') is True
            and ui.get('rendererExceptions') == [] and positive(ui.get('brokerProcessId'))
            and ui.get('automation') == 'unmodified consumer renderer; loopback CDP input'
            and {'action': 'file-drop', 'path': imported} in ui['steps'], 'Consumer UI input/ownership is incomplete')
        driver = load(f'workflow-{phase}/driver.json')
        require(driver.get('driver_sha256') == helpers['workflowUi.mjs'] and sha256(driver.get('input_sha256'))
            and sha256(driver.get('node_sha256')) and driver.get('broker_process_id') == ui['brokerProcessId']
            and positive(driver.get('broker_start_ticks')) and driver.get('package_full_name') == package
            and type(driver.get('exit_code')) is int and driver['exit_code'] == 0
            and driver.get('loopback_listener_verified') is True, 'UI driver source/process/exit is incomplete')
        args = driver['arguments']
        require(len(args) == 5 and args[:2] == ['--remote-debugging-port=0', '--remote-debugging-address=127.0.0.1']
            and args[2].startswith('--user-data-dir=') and args[3].startswith('--config-dir=')
            and args[4] == '--disable-networking', 'UI driver is not the fixed loopback consumer session')
        work_root = PureWindowsPath(original_path).parent.parent
        require(windows_path(args[2].split('=', 1)[1]) == windows_path(str(work_root / ('workflow-profile-'+phase)))
            and windows_path(args[3].split('=', 1)[1]) == windows_path(str(work_root / 'workflow-config')),
            'UI phases do not bind fresh profiles and the same persisted recipe configuration')
        brokers.append((driver['broker_process_id'], driver['broker_start_ticks']))
        modules = load(f'workflow-{phase}/loaded-modules.json')
        require(any(row.get('process_id') == ui['brokerProcessId'] and row.get('origin') == 'package'
            and row.get('relative_path') == 'Cliptern.exe' and row.get('sha256') == payload['Cliptern.exe']['sha256']
            and windows_path(row['path']) == windows_path(str(root / 'Cliptern.exe')) for row in modules),
            'Consumer broker lacks the exact installed executable observation')
    require(brokers[0] != brokers[1], 'Reopen did not use a fresh consumer process')
    trim = load('workflow-export/trim-entered.json')
    for end, value in [('start', '00:00:02.000'), ('end', '00:00:05.000')]:
        require(any(row.get('title') == f"Manually input current segment's {end} time" and row.get('value') == value
            and row.get('disabled') is False for row in trim['inputs']), 'Actual UI trim observation differs')
    selected = load('workflow-reopen/persisted-recipe-reapplied.json')['selects']
    require(any(row.get('id') == 'export-recipe' and row.get('value') == recipe['id'] for row in selected)
        and any(row.get('title') == 'Output container format:' and row.get('value') == 'mp4' for row in selected),
        'Persisted recipe selection/format observation is missing')
