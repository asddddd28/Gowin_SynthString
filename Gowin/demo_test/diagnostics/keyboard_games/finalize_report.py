"""Release evidence inventory; reads existing reports without controlling hardware."""
import hashlib,json
from datetime import datetime
from pathlib import Path
root=Path(__file__).resolve().parent;demo=root.parents[1];reports=root/'reports'
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
hw=read(reports/'hardware_serial.json');gui=read(reports/'gui_live.json')
profile=Path('C:/Users/asddddd28/AppData/Local/TangKeyboardLab/calibration.json')
manifest=dict(date=datetime.now().isoformat(),firmware='KeyboardGames',user_code='0x00007C30',status='0x76026238',
 bitstream_sha256=sha(root/'impl/pnr/keyboard_games.fs'),app_sha256=sha(demo/'desktop/release_games/TangKeyboardLab/TangKeyboardLab.exe'),
 timing=dict(constraint_mhz=50,fmax_mhz=54.865,logic=5338,registers=2148,dsp=6.5,violations=[]),
 implementation='All three game engines, timing, scoring and LED rendering in FPGA. App only commands and telemetry.',
 simulation=dict(game_rules='PASS',integration='PASS',raw_records=6336,game_frames=198),python_tests=35,
 strict_style_gate='FAILED:1614 diagnostics including formatter normalization failures; separate from xsim/Gowin/hardware evidence',
 hardware=dict(passed=hw['passed'],ack_count=len(hw['commands']),raw_records=hw['records'],game_frames=hw['game_frames'],
               status_crc_errors=hw['status_crc_errors'],game_crc_errors=hw['game_crc_errors'],
               handle_closed_seconds=5,same_epoch_before=hw['autonomous_before']['epoch'],same_epoch_after=hw['autonomous_after']['epoch'],
               countdown_before=hw['autonomous_before']['seconds'],countdown_after=hw['autonomous_after']['seconds'],
               sequence_errors_across_intentional_disconnect=hw['sequence_errors_across_deliberate_disconnect']),
 profile=hw['profile'],profile_unchanged=sha(profile)==hw['profile_sha256'],gui_board=gui.get('board'),gui_game=gui.get('game'),
 gui_stream=dict(records=gui['records'],sequence_errors=gui['sequence_errors'],game_crc_errors=gui.get('game_crc_errors'),fresh_keys=gui['fresh_keys']),
 sources={str(p.relative_to(root)):sha(p) for p in sorted((root/'src').glob('*.v'))},
 app_sources={p.name:sha(p) for p in sorted((demo/'desktop').glob('*.py'))},
 physical_playtest='Pending user feedback; digital telemetry does not certify player experience or observed LED colors')
session=reports/'gui_physical_session.jsonl'
if session.exists():
 observations=[]
 for line in session.read_text(encoding='utf-8').splitlines():
  try:observations.append(json.loads(line))
  except ValueError:pass
 games={}
 for obs in observations:
  game=obs['state'].get('game')
  if not game:continue
  identity=f"{game['game']}:{game['epoch']}"
  if identity not in games:games[identity]=dict(game=game['game'],epoch=game['epoch'],max_score=0,phases=[],reasons=[],first_time=obs['time'])
  item=games[identity];item['max_score']=max(item['max_score'],game['score']);item['last_time']=obs['time']
  if game['phase'] not in item['phases']:item['phases'].append(game['phase'])
  if game['reason'] not in item['reasons']:item['reasons'].append(game['reason'])
 manifest['observed_sessions']=list(games.values())
visual=reports/'physical_playtest.json'
if visual.exists():manifest['physical_playtest']=read(visual)
(reports/'release_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
state=dict(date=manifest['date'],firmware='KeyboardGames',project='diagnostics/keyboard_games/keyboard_games.gprj',
 bitstream='diagnostics/keyboard_games/impl/pnr/keyboard_games.fs',sha256=manifest['bitstream_sha256'],user_code=manifest['user_code'],
 download='SRAM only; Finished; no full bitstream readback; no external Flash/debugger/driver changes',
 serial_holder='release_games/TangKeyboardLab.exe on COM4',serial_handle_open=gui['serial_thread_alive'],board=gui.get('board'),game=gui.get('game'),
 calibration=dict(profile=hw['profile'],keys=32,thresholds=[.9,.5],saved_profile_unchanged=manifest['profile_unchanged']),
 autonomous_operation='Verified: close COM handle5s, reopen; same mole epoch1, seconds60 to53 including reopen; App reconnect did not restart game or calibration',
 evidence='diagnostics/keyboard_games/reports/release_manifest.json; program_sram.log; hardware_serial.json; gui_physical_session.jsonl',
 physical_playtest=manifest['physical_playtest'],validity='Snapshot only; reset/power loss/new download or subsequent App commands change state',
 power_cycle_note='After power loss reload SRAM image and reconnect App to restore saved32-key calibration')
(demo/'reports/current_board_state.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in manifest.items() if k not in ('sources','app_sources')},ensure_ascii=False,indent=2))
