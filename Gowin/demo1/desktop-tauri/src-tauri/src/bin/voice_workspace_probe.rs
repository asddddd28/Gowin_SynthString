//! Test-only stdin adapter to the same durable hardware session as the GUI.
use std::{io::{self,BufRead,Write},path::PathBuf};
use tang_synth_studio::voice_engine::{Engine,Action};
fn main(){
 let keep_audio=std::env::args().any(|arg|arg=="--keep-audio");
 let root=PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap()).join("SynthString/voice-engine");
 let mut engine=Engine::new(root);
 // Read status without the normal GUI disconnect/panic side effect. This
 // mode neither starts a fresh session nor stops an existing RAM loop.
 if std::env::args().nth(1).as_deref()==Some("--observe") {
  let port=std::env::args().nth(2).expect("--observe requires a port");
  let result=engine.connect(port,false);
  println!("{}",serde_json::json!({"ok":result.is_ok(),"error":result.err(),"view":engine.view()}));
  return;
 }
 for line in io::stdin().lock().lines(){
  let response=match line {
   Ok(line)=>match serde_json::from_str::<Action>(&line){
    Ok(action)=>match engine.action(action){Ok(view)=>serde_json::json!({"ok":true,"view":view}),Err(e)=>serde_json::json!({"ok":false,"error":e,"view":engine.view()})},
    Err(e)=>serde_json::json!({"ok":false,"error":e.to_string()}),
   },Err(_)=>break,
  };
  println!("{response}");io::stdout().flush().unwrap();
 }
 // Maintenance may resume a retained loop before releasing COM4 to the App.
 // Drop only the port in that explicit mode; ordinary probes still release notes.
 if engine.is_connected()&&!keep_audio{let _=engine.action(Action::Disconnect);}
}
