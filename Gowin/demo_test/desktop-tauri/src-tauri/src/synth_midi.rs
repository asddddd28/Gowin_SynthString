//! MIDI input is collected on the native callback; the editor owns key mapping/sustain.
use std::{collections::VecDeque,sync::{Arc,Mutex}};
#[derive(Default)]
pub struct Midi {connection:Option<midir::MidiInputConnection<()>>,events:Arc<Mutex<VecDeque<Vec<u8>>>>}
#[tauri::command]
pub async fn synth_midi_ports()->Result<Vec<String>,String>{let input=midir::MidiInput::new("Tang Studio input").map_err(|e|e.to_string())?;Ok(input.ports().iter().map(|p|input.port_name(p).unwrap_or_else(|_|"MIDI".into())).collect())}
#[tauri::command]
pub async fn synth_midi_connect(state:tauri::State<'_,Mutex<Midi>>,index:Option<usize>)->Result<(),String>{
 let mut state=state.lock().map_err(|e|e.to_string())?;state.connection=None;state.events.lock().map_err(|e|e.to_string())?.clear();
 if let Some(index)=index{let mut input=midir::MidiInput::new("Tang Studio input").map_err(|e|e.to_string())?;input.ignore(midir::Ignore::All);
  let ports=input.ports();let port=ports.get(index).ok_or("MIDI 设备已断开")?;let queue=state.events.clone();
  state.connection=Some(input.connect(port,"Tang Studio keyboard",move|_,message,_|{
   if message.len()<3{return;}if let Ok(mut queue)=queue.lock(){if queue.len()>=512{queue.clear();queue.push_back(vec![0xb0,123,0]);}else{queue.push_back(message[..3].to_vec());}}
  },()).map_err(|e|e.to_string())?);
 }Ok(())
}
#[tauri::command]
pub fn synth_midi_events(state:tauri::State<Mutex<Midi>>)->Result<Vec<Vec<u8>>,String>{let state=state.lock().map_err(|e|e.to_string())?;let mut queue=state.events.lock().map_err(|e|e.to_string())?;Ok(queue.drain(..).collect())}
