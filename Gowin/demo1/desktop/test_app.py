"""真实 Tk 控件 + 模拟串口，验证长按、映射、编辑和释放所有权。"""
import unittest
import queue
import copy
from unittest.mock import patch
from types import SimpleNamespace
import app


class RecordingLink:
    def __init__(self):
        self.frames = []
        self.events = queue.Queue()
    def send(self, frames):
        self.frames.extend(frames)
        return True
    def panic(self):
        self.frames.append(b'panic')
    def upload(self, samples):
        self.uploaded = samples
        return True
    def upload_pair(self, frames):
        self.pair=copy.deepcopy(frames)
        return True
    def upload_pcm(self, image):
        self.pcm = copy.deepcopy(image)
        return True
    def upload_profiles(self, profiles):
        self.profiles = copy.deepcopy(profiles)
        return True
    def close(self):
        pass


class AppTests(unittest.TestCase):
    def setUp(self):
        self.window = app.App()
        self.window.withdraw()
        self.window.config_data = app.defaults()
        self.window.link = RecordingLink()
        self.window.online = True
        self.window.synced_keys = set(range(32))

    def tearDown(self):
        self.window.update_idletasks()
        for job in self.window.tk.call('after', 'info'):
            self.window.after_cancel(job)
        self.window.destroy()

    def event(self, code, widget=None):
        return SimpleNamespace(keycode=code, keysym=chr(code), state=0, widget=widget or self.window)

    def test_repeat_and_release(self):
        w = self.window
        for _ in range(10):
            w.key_press(self.event(49))
        self.assertEqual(len(w.link.frames), 1)
        w.key_release(self.event(49))
        # A repeat press cancels a pending synthetic release.
        w.key_press(self.event(49))
        self.assertEqual(len(w.link.frames), 1)
        w.finish_release(49)
        self.assertEqual([p[1] for p in w.link.frames], [1, 2])

    def test_mouse_keyboard_same_note(self):
        w = self.window
        w.press(0, 'mouse'); w.press(0, 'keyboard')
        w.release(0, 'mouse')
        self.assertEqual(len(w.link.frames), 1)
        w.release(0, 'keyboard')
        self.assertEqual(len(w.link.frames), 2)

    def test_editor_and_all_release(self):
        w = self.window
        w.key_press(self.event(49, w.fields['name']))
        self.assertEqual(w.link.frames, [])
        for i in range(32):
            w.press(i, 'keyboard')
        w.release_all()
        self.assertEqual(len(w.link.frames), 64)
        self.assertEqual([p[2] for p in w.link.frames[:32]], list(range(32, 64)))
        self.assertFalse(w.held)

    def test_button_focus_plays_and_releases(self):
        w = self.window
        w.key_press(self.event(49, w.connect_button))
        w.key_release(self.event(49, w.connect_button))
        w.finish_release(49)
        self.assertEqual([p[1] for p in w.link.frames], [1, 2])

    def test_tk_dispatch_before_button_class(self):
        w = self.window
        w.deiconify()
        w.update()
        invoked = []
        w.connect_button.configure(command=lambda: invoked.append(True))
        w.connect_button.focus_force()
        w.update()
        w.connect_button.event_generate('<KeyPress-1>')
        w.connect_button.event_generate('<KeyRelease-1>')
        w.update()
        w.finish_release(49)
        self.assertEqual([p[1] for p in w.link.frames], [1, 2])
        w.config_data['keys'][0]['keycode'] = 32
        w.connect_button.event_generate('<KeyPress-space>')
        w.connect_button.event_generate('<KeyRelease-space>')
        w.update()
        w.finish_release(32)
        self.assertFalse(invoked)
        self.assertEqual([p[1] for p in w.link.frames], [1, 2, 1, 2])
        w.fields['name'].focus_force()
        w.update()
        w.fields['name'].event_generate('<KeyPress-1>')
        w.update()
        self.assertEqual(len(w.link.frames), 4)

    def test_windows_numlock_does_not_block_notes(self):
        w = self.window
        for state in (0x0008, 0x000A, 0x0028):
            event = self.event(49)
            event.state = state
            w.key_press(event)
            self.assertIn(0, w.held, f'Windows lock state {state:#x}')
            w.key_release(event)
            w.finish_release(49)
        self.assertEqual([p[1] for p in w.link.frames], [1, 2] * 3)

    def test_windows_ctrl_and_alt_do_not_play(self):
        w = self.window
        for state in (0x0004, 0x0010, 0x20000, 0x0018, 0x000C):
            event = self.event(49)
            event.state = state
            w.key_press(event)
        self.assertEqual(w.link.frames, [])

    def test_piano_preset_keeps_keys_and_volume(self):
        w = self.window
        original = copy.deepcopy(w.config_data['keys'])
        w.config_data['sound']['volume'] = 17
        w.press(0, 'keyboard')
        with patch.object(w, 'save_config') as save:
            w.apply_piano()
            save.assert_called_once()
        self.assertEqual([{k:v for k,v in x.items() if k!='synth'} for x in w.config_data['keys']], [{k:v for k,v in x.items() if k!='synth'} for x in original])
        self.assertTrue(w.profiles_uploading)
        self.assertEqual(len(w.link.profiles),32)
        self.assertEqual(w.config_data['sound'], app.piano_sound(17))
        self.assertFalse(w.held)
        self.assertEqual(w.link.frames[1][1], 2)
        self.assertEqual(w.link.frames[2:], app.sound_packets(app.piano_sound(17)))

    def test_upload_releases_and_blocks_new_notes(self):
        w=self.window;w.press(0,'keyboard')
        w.start_table_upload([0]*1024)
        self.assertTrue(w.uploading)
        w.press(1,'keyboard')
        self.assertEqual([p[1] for p in w.link.frames],[1,2])
        with patch.object(w,'save_config'):
            w.link.events.put(('upload_done','ok'));w.poll()
        self.assertFalse(w.uploading)
        self.assertEqual(w.config_data['keys'][0]['synth']['wave_a'],'自定义波表')
        self.assertTrue(w.profiles_uploading)

    def test_perkey_upload_ack_and_volume_preserves_patches(self):
        w=self.window
        w.config_data['keys'][0]['synth']=app.preset('FM 电钢琴')
        w.upload_profiles([0])
        self.assertTrue(w.profiles_uploading)
        self.assertNotIn(0,w.synced_keys)
        self.assertEqual(w.link.profiles[0][0],32)
        w.press(0,'keyboard');self.assertFalse(w.held)
        w.link.events.put(('profiles_done','ok'));w.poll()
        self.assertIn(0,w.synced_keys)
        w.press(0,'keyboard');self.assertIn(0,w.held)
        patches=copy.deepcopy(w.config_data['keys'])
        w.sound_vars['volume'].set(13)
        w.output_boost.current(3)
        with patch.object(w,'save_config'):w.apply_volume()
        self.assertEqual(w.config_data['keys'],patches)
        self.assertEqual(w.link.frames[-1],app.packet(3,0,value=round(13*65535/100)))
        self.assertEqual(w.link.frames[-2],app.packet(3,12,value=3))
        self.assertEqual(w.config_data['sound']['output_boost'],3)

    def test_table_target_survives_selection_change(self):
        w=self.window;w.start_table_upload([0]*1024)
        w.select_key(5)
        with patch.object(w,'save_config'):
            w.link.events.put(('upload_done','ok'));w.poll()
        self.assertEqual(w.link.profiles[0][0],32)
        self.assertEqual(w.config_data['keys'][5]['synth']['wave_a'],'正弦')

    def test_failed_profile_upload_does_not_enable_key(self):
        w=self.window;w.upload_profiles([2])
        w.link.events.put(('profiles_error','bad crc'));w.poll()
        w.press(2,'keyboard')
        self.assertFalse(w.held)
        self.assertNotIn(2,w.synced_keys)
        self.assertIn(1,w.synced_keys)

    def test_minimum_window_keeps_parameter_actions_visible(self):
        w=self.window
        width,height=w.minsize();w.geometry(f'{width}x{height}');w.deiconify();w.update()
        def walk(widget):
            for child in widget.winfo_children():
                yield child
                yield from walk(child)
        for page in w.view.PAGES:
            w.view.show_page(page);w.update()
            targets=[x for x in walk(w) if isinstance(x,app.ttk.Button) and x.winfo_ismapped()]
            self.assertGreater(len(targets),5)
            for button in targets:
                child=button
                while child is not w:
                    parent=child.master
                    self.assertLessEqual(child.winfo_y()+child.winfo_height(),parent.winfo_height(),button.cget('text'))
                    self.assertLessEqual(child.winfo_x()+child.winfo_width(),parent.winfo_width(),button.cget('text'))
                    child=parent

    def test_page_switch_releases_notes_and_disables_hidden_performance_keys(self):
        w=self.window;w.key_press(self.event(49));self.assertTrue(w.held)
        w.view.show_page('resources');self.assertFalse(w.held)
        self.assertEqual([p[1] for p in w.link.frames],[1,2])
        w.key_press(self.event(50));self.assertFalse(w.held)
        w.view.show_page('settings');w.key_press(self.event(50));self.assertFalse(w.held)
        w.view.show_page('perform');w.key_press(self.event(50));self.assertIn(1,w.held)
        w.capture();w.view.show_page('settings');self.assertFalse(w.capturing)
        self.assertEqual(w.shortcut_text.get(),w.config_data['keys'][w.selected]['shortcut'])

    def test_inspector_requires_hardware_ack_and_updates_after_disconnect(self):
        w=self.window;w.select_key(6);w.upload_profiles([6]);w.view.refresh()
        self.assertIn('传输中',w.view.key_state.cget('text'))
        self.assertTrue(w.view.upload_key.instate(['disabled']))
        w.link.events.put(('profiles_done','ok'));w.poll()
        self.assertIn('已由硬件确认',w.view.key_state.cget('text'))
        self.assertTrue(w.view.upload_key.instate(['!disabled']))
        w.disconnect()
        self.assertIn('待同步',w.view.key_state.cget('text'))
        self.assertEqual(w.view.sync_count.cget('text'),'0 / 32 已同步')
        self.assertTrue(w.view.upload_key.instate(['disabled']))

    def test_basic_bank_search_keeps_resource_identity(self):
        w=self.window;w.open_basic_panel();panel=w.basic_panel
        try:
            sound=panel.sounds[12];panel.query.set(sound.title)
            self.assertIn('12',panel.tree.get_children())
            panel.tree.selection_set('12');self.assertIs(panel.selected(),sound)
            played=[];panel.play=played.append;panel.preview()
            self.assertEqual(played,[sound.preview])
            panel.query.set('no-such-timbre-938472')
            self.assertEqual(panel.tree.get_children(),())
            self.assertIn('没有匹配',panel.info.get('1.0','end'))
            panel.query.set('');self.assertEqual(len(panel.tree.get_children()),16)
        finally:panel.close()

    def test_editor_saves_only_selected_key(self):
        w=self.window;w.select_key(4);before=copy.deepcopy(w.config_data['keys'])
        w.edit_synth()
        dialog=next(x for x in w.winfo_children() if isinstance(x,app.tk.Toplevel))
        form=dialog.winfo_children()[0]
        controls=form.winfo_children()
        selector=next(x for x in controls if isinstance(x,app.ttk.Combobox) and 'FM 电钢琴' in x.cget('values'))
        selector.set('FM 电钢琴')
        next(x for x in controls if isinstance(x,app.ttk.Button) and x.cget('text')=='载入预设到编辑框').invoke()
        with patch.object(w,'save_config'):
            next(x for x in controls if isinstance(x,app.ttk.Button) and x.cget('text')=='保存并上传此键').invoke()
        self.assertEqual(w.config_data['keys'][4]['synth'],app.preset('FM 电钢琴'))
        self.assertEqual(w.link.profiles[0][0],36)
        for i in range(32):
            if i!=4:self.assertEqual(w.config_data['keys'][i],before[i])

    def test_pcm_upload_and_missing_image_guard(self):
        from test_pcm import fixture
        w=self.window
        w.config_data['keys'][0]['synth']=app.preset('采样钢琴')
        w.press(0,'keyboard');self.assertFalse(w.held)
        w.start_pcm_upload(fixture());self.assertTrue(w.uploading)
        w.select_key(2)
        with patch.object(w,'save_config'):
            w.link.events.put(('pcm_done','ok'));w.poll()
        self.assertTrue(w.pcm_available)
        self.assertEqual(w.link.profiles[0][0],32)
        self.assertTrue(w.profiles_uploading)
        w.link.events.put(('profiles_done','ok'));w.poll()
        w.press(0,'keyboard');self.assertIn(0,w.held)

    def test_pair_upload_keeps_target_until_confirmed(self):
        w=self.window;w.select_key(5)
        before=copy.deepcopy(w.config_data['keys'])
        w.start_pair_upload([[0]*1024,[1]*1024])
        self.assertTrue(w.uploading);self.assertEqual(w.table_total,2048)
        self.assertEqual(len(w.link.pair),2)
        w.select_key(7)
        self.assertEqual(w.config_data['keys'],before)
        with patch.object(w,'save_config'):
            w.link.events.put(('upload_done','ok'));w.poll()
        self.assertEqual(w.config_data['keys'][5]['synth']['wave_a'],'自定义波表')
        self.assertEqual(w.link.profiles[0][0],37)
        self.assertEqual(w.config_data['keys'][7],before[7])

    def test_editor_frame_position_only_changes_selected_key(self):
        w=self.window;w.select_key(9);before=copy.deepcopy(w.config_data['keys'])
        w.edit_synth()
        dialog=next(x for x in w.winfo_children() if isinstance(x,app.tk.Toplevel))
        form=dialog.winfo_children()[0];widgets=form.winfo_children()
        label=next(x for x in widgets if isinstance(x,app.ttk.Label) and x.cget('text').startswith('双帧位置'))
        entry=next(x for x in widgets if isinstance(x,app.ttk.Entry) and x.grid_info()['row']==label.grid_info()['row'] and x.grid_info()['column']==label.grid_info()['column']+1)
        entry.delete(0,'end');entry.insert(0,'75')
        with patch.object(w,'save_config'):
            next(x for x in widgets if isinstance(x,app.ttk.Button) and x.cget('text')=='保存并上传此键').invoke()
        self.assertEqual(w.config_data['keys'][9]['synth']['frame_position'],75)
        self.assertEqual(w.link.profiles[0][0],41)
        for i in range(32):
            if i!=9:self.assertEqual(w.config_data['keys'][i],before[i])

    def test_library_upload_fraction_only_after_resource_ack(self):
        w=self.window; w.select_key(3)
        before=copy.deepcopy(w.config_data['keys'])
        w.online=False
        self.assertFalse(w.start_pair_upload([[0]*1024,[1]*1024],12345))
        self.assertEqual(w.config_data['keys'],before)
        w.online=True
        self.assertTrue(w.start_pair_upload([[0]*1024,[1]*1024],12345))
        self.assertFalse(w.start_pair_upload([[0]*1024,[1]*1024],0))
        self.assertEqual(w.config_data['keys'],before)
        w.select_key(5)
        with patch.object(w,'save_config'):
            w.link.events.put(('upload_done','ok')); w.poll()
        self.assertAlmostEqual(w.config_data['keys'][3]['synth']['frame_position']*65535/100,12345)
        self.assertEqual(w.config_data['keys'][5],before[5])
        self.assertEqual(w.link.profiles[0][0],35)
        self.assertTrue(w.profiles_uploading)

    def test_library_panel_preview_failed_load_and_lifecycle(self):
        from pathlib import Path
        import tempfile
        from wavetable_bank import encode_bank
        w=self.window; w.open_library_panel(); p=w.library_panel; p.withdraw()
        w.open_library_panel(); self.assertIs(w.library_panel,p)
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'test.tswt'
            source.write_bytes(encode_bank([[i]*1024 for i in range(3)]))
            p.load(source); p.position.set(75)
            frames,job=p.selected_pair()
            self.assertEqual([f[0] for f in frames],[1,2]); self.assertEqual(job['fraction'],32768)
            self.assertGreater(len(p.canvas.find_all()),0)
            p.position.set(100); frames,job=p.selected_pair()
            self.assertEqual([f[0] for f in frames],[2,2]); self.assertEqual(job['fraction'],0)
            original=p.resources
            source.write_bytes(b'corrupt')
            with self.assertRaises(ValueError): p.load(source)
            self.assertIs(p.resources,original)
            w.online=False; p.upload_selected()
            self.assertIn('连接',p.status.get()); self.assertFalse(w.uploading)
        p.close(); self.assertIsNone(w.library_panel)

    def test_capture_and_panic(self):
        w = self.window
        w.capture()
        w.key_press(self.event(112))
        self.assertEqual(w.capture_code, 112)
        self.assertEqual(w.link.frames, [])
        w.press(3, 'mouse')
        w.panic()
        self.assertFalse(w.held)
        self.assertEqual(w.link.frames[-1], b'panic')

    def test_surge_envelope_upload_only_selected_key_and_ack_required(self):
        from test_surge_bridge import fixture
        w = self.window
        w.select_key(6)
        before = copy.deepcopy(w.config_data['keys'])
        with patch.object(w, 'save_config'):
            w.apply_surge_envelope(fixture())
        self.assertEqual(w.link.profiles[0][0], 38)
        self.assertTrue(w.profiles_uploading)
        self.assertNotIn(6, w.synced_keys)
        self.assertAlmostEqual(w.config_data['keys'][6]['synth']['decay'], 1000)
        for i in range(32):
            if i != 6:
                self.assertEqual(w.config_data['keys'][i], before[i])
        w.link.events.put(('profiles_done', 'ok'))
        w.poll()
        self.assertIn(6, w.synced_keys)

    def test_surge_save_failure_and_busy_do_not_change_configuration(self):
        from test_surge_bridge import fixture
        w = self.window
        before = copy.deepcopy(w.config_data)
        with patch.object(w, 'save_config', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                w.apply_surge_envelope(fixture())
        self.assertEqual(w.config_data, before)
        w.uploading = True
        with self.assertRaises(ValueError):
            w.apply_surge_envelope(fixture())
        self.assertEqual(w.config_data, before)

    def test_surge_panel_lifecycle_and_preview(self):
        from test_surge_bridge import fixture
        w = self.window
        w.open_surge_panel()
        panel = w.surge_panel
        try:
            panel.snapshot = fixture()
            panel.render()
            self.assertIn('1000.000', panel.preview.get('1.0','end'))
            w.open_surge_panel()
            self.assertIs(w.surge_panel, panel)
            w.select_key(2)
            panel.after_cancel(panel.job)
            panel.poll()
            self.assertIn('03', panel.target.get())
        finally:
            panel.close()
        self.assertIsNone(w.surge_panel)


    def test_basic_resource_requires_ack_and_captured_target(self):
        from basic_bank import load_basic_bank
        from pathlib import Path
        w=self.window;w.select_key(4)
        sound=load_basic_bank(Path(app.__file__).resolve().parents[1]/'output/basic_bank_v1')[12]
        profile,frames=sound.upload();before=copy.deepcopy(w.config_data)
        self.assertTrue(w.apply_basic_timbre(profile,frames))
        profile['attack']=1;frames[0][0]=99999
        self.assertEqual(w.config_data,before)
        self.assertFalse(hasattr(w.link,'profiles'))
        w.select_key(7)
        with patch.object(w,'save_config'):
            w.link.events.put(('upload_done','ok'));w.poll()
        self.assertEqual(w.link.profiles[0][0],36)
        self.assertEqual(w.link.profiles[0][1],sound.profile)
        self.assertEqual(w.config_data['keys'][7],before['keys'][7])
        self.assertNotIn(4,w.synced_keys);self.assertTrue(w.profiles_uploading)
        w.link.events.put(('profiles_done','ok'));w.poll()
        self.assertIn(4,w.synced_keys);self.assertIsNone(w.pending_basic_patch)

    def test_basic_rejected_queue_offline_busy_and_save_failure(self):
        w=self.window;before=copy.deepcopy(w.config_data);profile=dict(app.preset('FM 贝斯'),frame_position=0)
        w.online=False;self.assertFalse(w.apply_basic_timbre(profile));w.online=True
        w.profiles_uploading=True;self.assertFalse(w.apply_basic_timbre(profile));w.profiles_uploading=False
        with patch.object(w,'save_config',side_effect=OSError('disk full')):
            with self.assertRaises(OSError):w.apply_basic_timbre(profile)
        self.assertEqual(w.config_data,before);self.assertFalse(hasattr(w.link,'profiles'))
        with patch.object(w,'save_config') as save,patch.object(w.link,'upload_profiles',return_value=False):
            self.assertFalse(w.apply_basic_timbre(profile));self.assertEqual(save.call_count,2)
        self.assertEqual(w.config_data,before);self.assertEqual(w.synced_keys,set(range(32)))
        self.assertFalse(w.profiles_uploading)

    def test_basic_parameter_only_then_profile_error_blocks_key(self):
        w=self.window;w.select_key(3);before=copy.deepcopy(w.config_data)
        profile=dict(app.preset('FM 电钢琴'),frame_position=0)
        with patch.object(w,'save_config'):
            self.assertTrue(w.apply_basic_timbre(profile))
        self.assertFalse(hasattr(w.link,'pair'));self.assertTrue(w.profiles_uploading)
        self.assertEqual(w.link.profiles,[(35,profile)])
        for index in range(32):
            if index!=3:self.assertEqual(w.config_data['keys'][index],before['keys'][index])
        w.link.events.put(('profiles_error','timeout'));w.poll()
        self.assertNotIn(3,w.synced_keys);w.press(3,'keyboard');self.assertFalse(w.held)

    def test_basic_wave_failure_disconnect_and_late_duplicate_ack(self):
        w=self.window;before=copy.deepcopy(w.config_data)
        profile=dict(app.preset('正弦'),wave_a='自定义波表',attack=250,frame_position=0)
        self.assertTrue(w.apply_basic_timbre(profile,[[0]*1024,[1]*1024]))
        w.link.events.put(('upload_error','CRC failed'));w.poll()
        self.assertEqual(w.config_data,before);self.assertIsNone(w.pending_basic_patch)
        w.link.events.put(('upload_done','late ack'));w.poll()
        self.assertEqual(w.config_data,before)
        self.assertTrue(w.apply_basic_timbre(profile,[[0]*1024,[1]*1024]))
        w.disconnect();self.assertIsNone(w.pending_basic_patch)
        self.assertEqual(w.config_data,before)

    def test_basic_wave_ack_save_failure_retains_original_and_unsynced(self):
        w=self.window;w.select_key(8);before=copy.deepcopy(w.config_data)
        profile=dict(app.preset('正弦'),wave_a='自定义波表',attack=250,frame_position=0)
        self.assertTrue(w.apply_basic_timbre(profile,[[0]*1024,[1]*1024]))
        with patch.object(w,'save_config',side_effect=OSError('disk full')):
            w.link.events.put(('upload_done','ok'));w.poll()
        self.assertEqual(w.config_data,before);self.assertNotIn(8,w.synced_keys)
        self.assertFalse(hasattr(w.link,'profiles'));self.assertIn('保存失败',w.hint.get())
        self.assertIsNone(w.pending_basic_patch)

    def test_basic_panel_offline_preview_upload_and_failed_reload(self):
        from pathlib import Path
        import tempfile
        w=self.window;w.open_basic_panel();panel=w.basic_panel;panel.withdraw()
        w.open_basic_panel();self.assertIs(w.basic_panel,panel)
        self.assertEqual(len(panel.tree.get_children()),16)
        played=[];stopped=[];panel.play=played.append;panel.stop=lambda:stopped.append(True)
        w.online=False;panel.preview();self.assertEqual(played,[panel.sounds[0].preview])
        self.assertFalse(hasattr(w.link,'profiles'));panel.upload();self.assertIn('连接',panel.status.get())
        original=panel.sounds
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'BASICS.JSN';path.write_text('{}',encoding='utf-8')
            with self.assertRaises(ValueError):panel.load(path)
        self.assertIs(panel.sounds,original)
        w.online=True;w.select_key(5);panel.tree.selection_set('9')
        panel.show_info()
        with patch.object(w,'save_config'):
            panel.upload();self.assertTrue(w.uploading)
            w.link.events.put(('upload_done','ok'));w.poll()
        self.assertEqual(w.link.profiles[0][0],37)
        panel.close();self.assertIsNone(w.basic_panel);self.assertTrue(stopped)


if __name__ == '__main__':
    unittest.main()
