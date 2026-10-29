"""Headless controller regression with real assets and recorded serial traffic."""
import copy
import io
import json
from pathlib import Path
import queue
import tempfile
import time
import unittest
from unittest.mock import patch

from studio_engine import StudioEngine
from studio_service import serve
from protocol import packet
from test_app import RecordingLink
from surge_bridge import SurgeSnapshot
from test_surge_bridge import fixture


class StudioEngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        # The test can run before a package build: use source assets via a tiny
        # directory layout with junction-free copies of the two catalogs.
        import shutil
        root = Path(__file__).resolve().parents[1]
        self.assets = Path(self.temp.name) / 'assets'
        shutil.copytree(root / 'output/basic_bank_v1', self.assets / 'basic_bank')
        shutil.copytree(root / 'output/sd_library_demo', self.assets / 'wavetable_library')
        self.engine = StudioEngine(self.assets, Path(self.temp.name) / 'settings.json')
        self.engine.link = RecordingLink()
        self.engine.online = True

    def tearDown(self):
        self.engine.close()
        self.temp.cleanup()

    def test_editor_commit_atomic_validation_and_disk_failure(self):
        e = self.engine
        before = copy.deepcopy(e.config)
        key = copy.deepcopy(before['keys'][4]); key['synth']['depth'] = 100
        with self.assertRaises(ValueError): e.save_key(4, key)
        self.assertEqual(e.config, before)
        key['synth']['depth'] = .7
        with patch.object(Path, 'replace', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): e.save_key(4, key)
        self.assertEqual(e.config, before)
        e.save_key(4, key)
        self.assertEqual(e.config['keys'][4]['synth']['depth'], .7)
        self.assertEqual(e.config['keys'][5], before['keys'][5])
        self.assertEqual(e.revision, 1)
        self.assertEqual(json.loads(e.config_path.read_text(encoding='utf-8')), e.config)

    def test_keyboard_mouse_ownership_ack_and_watchdog(self):
        e = self.engine
        with self.assertRaises(ValueError): e.note_on(0, 'keyboard')
        e.sync([0]); e.handle_event('profiles_done', 'ok')
        e.note_on(0, 'keyboard'); e.note_on(0, 'keyboard'); e.note_on(0, 'mouse')
        self.assertEqual(e.link.frames, [packet(1, 32, 48, 96)])
        e.note_off(0, 'keyboard'); self.assertTrue(e.held)
        e.note_off(0, 'mouse'); self.assertFalse(e.held)
        self.assertEqual(e.link.frames[-1], packet(2, 32))
        e.note_on(0, 'keyboard'); e.last_ui = time.monotonic() - 2; e.tick()
        self.assertFalse(e.held); self.assertIn('心跳超时', e.message)

    def test_preset_local_binding_reloads_and_upload_requires_both_acks(self):
        e = self.engine
        sound = e.bank[12]
        e.load_preset(4, sound.timbre_id)
        self.assertEqual(e.config['tauri_bindings']['4'], sound.timbre_id)
        reloaded = StudioEngine(self.assets, e.config_path)
        self.assertEqual(reloaded.config, e.config); reloaded.close()
        e.sync([4]); self.assertEqual(e.transfer, 'wavetable')
        self.assertFalse(hasattr(e.link, 'profiles'))
        with self.assertRaises(ValueError): e.save_key(4, e.config['keys'][4])
        e.handle_event('upload_done','ok')
        self.assertEqual(e.transfer, 'profiles')
        self.assertEqual(e.link.profiles[0][0],36)
        self.assertNotIn(4,e.synced)
        e.handle_event('profiles_done','ok'); e.note_on(4,'keyboard')
        self.assertIn(4,e.held)

    def test_shared_wave_replacement_invalidates_previous_keys(self):
        e = self.engine
        e.load_preset(2,e.bank[8].timbre_id); e.sync([2])
        e.handle_event('upload_done','ok'); e.handle_event('profiles_done','ok')
        e.load_preset(3,e.bank[9].timbre_id)
        with self.assertRaises(ValueError): e.sync([2,3])
        e.sync([3]); e.handle_event('upload_done','ok'); e.handle_event('profiles_done','ok')
        self.assertNotIn(2,e.synced); self.assertIn(3,e.synced)
        with self.assertRaises(ValueError): e.note_on(2,'keyboard')

    def test_wave_upload_failure_and_late_ack_do_not_commit(self):
        e = self.engine; before = copy.deepcopy(e.config)
        e.upload_wave(7,0,65)
        self.assertEqual(e.config,before)
        e.handle_event('upload_error','crc failed'); e.handle_event('upload_done','late')
        self.assertEqual(e.config,before); self.assertIsNone(e.active_resource)
        self.assertFalse(hasattr(e.link,'profiles'))

    def test_wave_ack_save_failure_blocks_custom_keys(self):
        e = self.engine; before=copy.deepcopy(e.config)
        e.upload_wave(7,0,65)
        with patch.object(e,'commit',side_effect=OSError('full')):
            e.link.events.put(('upload_done','ok')); e.tick()
        self.assertEqual(e.config,before); self.assertNotIn(7,e.synced)
        self.assertEqual(e.level,'error'); self.assertIsNone(e.transfer)

    def test_resource_position_and_captured_target(self):
        e=self.engine; e.upload_wave(7,0,75)
        p=e.wave_preview(0,75)
        self.assertEqual(len(p['frames'][0]),256)
        e.handle_event('upload_done','ok')
        self.assertEqual(e.link.profiles[0][0],39)
        self.assertEqual(e.config['keys'][7]['synth']['wave_a'],'自定义波表')
        self.assertNotEqual(e.config['keys'][6]['synth']['wave_a'],'自定义波表')
        with self.assertRaises(ValueError): e.wave_preview(0,float('nan'))

    def test_disconnect_clears_confirmation_and_residency(self):
        e=self.engine; e.synced={1,2}; e.active_resource=9
        e.disconnect()
        self.assertFalse(e.online); self.assertFalse(e.synced); self.assertIsNone(e.active_resource)
        with self.assertRaises(ValueError): e.sync([1])

    def test_output_leaves_per_key_profiles_untouched(self):
        e=self.engine; before=copy.deepcopy(e.config['keys'])
        e.set_output(17,2)
        self.assertEqual(e.config['keys'],before)
        self.assertEqual(e.link.frames, [packet(3,12,value=2),packet(3,0,value=round(17*65535/100))])
        with self.assertRaises(ValueError): e.set_output(101,2)
        self.assertEqual(e.config['sound']['volume'],17)

    def test_surge_actual_messages_shape_and_mapping(self):
        e=self.engine
        class Reader:
            events=queue.Queue()
            def close(self): pass
        e.surge=Reader()
        snapshot=fixture()
        messages=[(address,[data['value'],data['display']]) for address,data in snapshot.parameters.items()]
        messages += [('/doc'+address,[data['name'],data['type'],data['minimum'],data['maximum']]) for address,data in snapshot.docs.items()]
        e.surge.events.put(('messages',messages)); e.tick()
        before=copy.deepcopy(e.config)
        e.surge_apply(6)
        self.assertAlmostEqual(e.config['keys'][6]['synth']['decay'],1000)
        self.assertEqual(e.config['keys'][5],before['keys'][5])
        self.assertNotIn(6,e.synced)

    def test_service_contract_errors_and_eof_cleanup(self):
        e=self.engine; e.synced.add(0); e.note_on(0,'keyboard')
        source=io.StringIO('\n'.join([json.dumps({'method':'get_state'}),json.dumps({'method':'__dict__'}),'not json'])+'\n')
        sink=io.StringIO(); serve(e,source,sink)
        responses=[json.loads(line) for line in sink.getvalue().splitlines()]
        self.assertTrue(responses[0]['ok']);self.assertEqual(responses[0]['result']['held'],[0])
        self.assertFalse(responses[1]['ok']);self.assertFalse(responses[2]['ok'])
        self.assertFalse(e.held);self.assertFalse(e.online)


if __name__ == '__main__': unittest.main()
