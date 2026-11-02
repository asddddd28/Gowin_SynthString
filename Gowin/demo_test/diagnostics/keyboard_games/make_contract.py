"""Explicit game interface contract plus preserved calibrated-keyboard contracts."""
import json
from pathlib import Path
root=Path(__file__).resolve().parent
contract=json.loads((root.parent/'keyboard_reactive/contract.json').read_text(encoding='utf-8'))
contract['name']='keyboard_games'
for module in contract['modules']:
    if module['name']=='KeyboardReactive':
        module['name']='KeyboardGames';module['rtl_path']='src/KeyboardGames.v'
        module['behavior']+=['GameEngine owns all game rules and timers; GameDisplay snapshots its palette image.', 'App disconnect never resets games; telemetry shares UART at record boundaries.']
    if module['name']=='KeyController':
        module['interfaces']['ports'] += [dict(name=name,direction='output',width=width,role='data',description=description) for name,width,description in (
            ('o_game_start',1,'One-cycle start for a fresh accepted command41'),('o_game_stop',1,'One-cycle stop on42, ordinary effect or calibration commit'),('o_game_type',2,'1snake2mole3piano'))]
        module['behavior']+=['Command41 starts selected game and mode5 only after calibration. Duplicate replay does not restart.', 'Command42 restores chosen ordinary mode0..4; normal EFFECT/COMMIT stop current game.']
    if module['name']=='KeyboardTelemetry':
        module['interfaces']['ports'].append(dict(name='i_game_status',direction='input',width=128,role='data',description='Game metadata and32 two-bit pixels'))
        module['behavior']+=['Every scan includes #32HEX*CRC LF game status, CRC over16bytes.', 'ACK > normal status > game status > raw; game payload snapshotted before CRC/serialization.']
        module['verification_cases']+=['Integrated UART CRC128 decoder, game epoch/mode/score and calibrated ADC piano play.']

def add(name,ports,behavior,constraints,cases,waves):
    module=dict(name=name,rtl_path=f'src/{name}.v',interfaces=dict(ports=[dict(name=n,direction=d,width=w,role='clock' if n=='i_clk' else 'reset' if n=='i_rstn' else 'data',description=desc) for n,d,w,desc in ports]),
        clock=dict(name='i_clk',frequency_mhz=50,edge='posedge'),reset=dict(name='i_rstn',active='low',synchronous=False,description='Top provides synchronized release'),
        behavior=behavior,constraints=constraints,corner_cases=['Reset clears all game state and pixels.',*constraints],verification_cases=cases,
        timing_diagrams=[dict(id='operation',title=name,scenario='operation',description='Conceptual phases; frame tick is50Hz in hardware.',wavejson=dict(signal=waves))])
    contract['modules'].append(module)

common=[('i_clk','input',1,'50MHz clock'),('i_rstn','input',1,'Active-low reset')]
add('GameEngine',common+[(n,'input',w,d) for n,w,d in [('i_start',1,'Start selected game'),('i_stop',1,'Stop, priority over start'),('i_game',2,'1snake2mole3piano'),('i_frame_tick',1,'50Hz enable pulse'),('i_press',32,'Qualified rising press pulses'),('i_pressed',32,'Held key bitmap')]]+[
    ('o_pixels','output',64,'Key0bits1:0; palette0black1green2red3cyan'),('o_status','output',128,'game,phase,seconds,reason,score16,misses,epoch,pixels64')],
    ['Three-second countdown; game state advances entirely on FPGA clock and50Hz frame enables.',
     'Snake uses28-cell arena excluding K23/K30/K31/K32 controls; green body, red apple, collision and full-board win detection.',
     'Only one direction queued per movement, no reversal; exactly coincident direction input queues for next move.',
     'Mole lasts3000 frame ticks: green10/80ticks, red30/45ticks, cyan20/60ticks; spawn30ticks, held cells excluded.',
     'Mole simultaneous scores/expiries use balanced reduction trees; hit wins expiry, final deadline suppresses hits.',
     'Piano bottom keys only; successful press shifts notes and adds1; wrong/multiple/expired press ends. Deadline90ticks down to25.',
     'Failure flashes red at2.5Hz for2seconds; success/timeout settlement green. Score retained until next game.',
     'LFSR free-runs; free-cell placement probes one cell per clock to avoid long combinational search.'],
    ['i_frame_tick must be50Hz for wall-clock durations.', 'Start requires calibrated configuration, enforced by KeyController.', 'Palette and4x8 physical mapping fixed; no internet, CPU or App timing dependency.'],
    ['tb_game_engine: countdown, growth, queued turns, reverse rejection, wall/self/tail/full-board, color scores, concurrent hits, expiry, held exclusion, exact60seconds, piano shift/errors/timeout/last-tick hit, stop/reset.',
     'tb_keyboard_games: actualUART game command/CRC/epoch plus ADC-qualified piano input.'],
    [dict(name='phase',wave='=.=.=.=.',data=['start','countdown3s','running','result']),dict(name='frame_tick',wave='01010101'),dict(name='press',wave='0...10..')])
add('GameDisplay',common+[(n,'input',w,d) for n,w,d in [('i_enable',1,'Game owns LEDs'),('i_frame_tick',1,'Capture whole frame'),('i_pixels',64,'32palette pixels'),('i_pixel',5,'LED index')]]+[
    ('o_active','output',1,'Frame-frozen source selection'),('o_grb','output',24,'Palette GRB data')],
    ['Capture enable and all64pixel bits on frame tick; hold until next tick.', 'Palette uses green/red/cyan at32/255 channel level. Top source mux uses captured ownership.'],
    ['Source pixels must be synchronous; LED transmitter loads after snapshot cycle.'],
    ['All four palette values, enable/image changes between ticks do not tear frame, reset clears source.'],
    [dict(name='frame_tick',wave='010...10'),dict(name='pixels',wave='x.=.=... ',data=['imageA','imageB']),dict(name='snapshot',wave='x.=...=.',data=['imageA','imageB'])])
(root/'contract.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
