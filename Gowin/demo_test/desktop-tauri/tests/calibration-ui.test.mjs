import {test} from 'node:test';
import assert from 'node:assert/strict';
import {calibrationAvailability} from '../src/calibrationUi.ts';

const snapshot = () => ({
  connection:'live', now:10, board_updated:9.95, board:{mode:2},
  keys:Array.from({length:32},()=>({fresh:true})),
  transfer:{busy:false,completed:35,total:35}, calibration:null,
});
test('finished game still needs an explicit exit before calibration',()=>{
  const s=snapshot();s.board.mode=5;s.game={phase:3};
  const v=calibrationAvailability(s,[0]);
  assert.ok(v.startReason.includes('小游戏'));assert.ok(v.canExitGame);
  s.board.mode=2;assert.equal(calibrationAvailability(s,[0]).startReason,'');
});
test('replay, stale status and missing keys cannot start or apply',()=>{
  for(const change of [s=>s.connection='replay',s=>s.board_updated=1,s=>s.keys[0].fresh=false]){
    const s=snapshot();s.calibration={stage:'press',targets:[0],done:[0]};change(s);
    const v=calibrationAvailability(s,[0]);assert.ok(v.startReason);assert.ok(v.applyReason);
  }
});
test('busy commands disable game exit until an ACK is available',()=>{
  const s=snapshot();s.board.mode=5;s.transfer.busy=true;
  assert.equal(calibrationAvailability(s,[0]).canExitGame,false);
  assert.ok(calibrationAvailability(s,[0]).blocked.includes('板卡确认'));
});
test('calibration advances rest -> ready -> press -> complete',()=>{
  const s=snapshot();s.calibration={stage:'rest',targets:[0,1],done:[]};
  assert.ok(calibrationAvailability(s,[0,1]).startReason);
  assert.ok(calibrationAvailability(s,[0,1]).pressReason);
  s.calibration.stage='ready';assert.equal(calibrationAvailability(s,[0,1]).pressReason,'');
  s.calibration.stage='press';s.calibration.done=[0];assert.ok(calibrationAvailability(s,[0,1]).applyReason.includes('1'));
  s.calibration.done=[0,1];assert.equal(calibrationAvailability(s,[0,1]).applyReason,'');
});
test('failed candidate can restart without overwriting saved calibration',()=>{
  const s=snapshot();s.calibration={stage:'error',targets:[0],done:[]};
  assert.equal(calibrationAvailability(s,[0]).startReason,'');
  assert.ok(calibrationAvailability(s,[0]).applyReason);
});
