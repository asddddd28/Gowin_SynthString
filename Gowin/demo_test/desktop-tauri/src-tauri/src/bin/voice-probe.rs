//! Board integration exerciser using exactly the GUI session and command backend.
use tang_hardware_lab::voice_engine::{Action,Engine,library};
use std::{path::PathBuf,thread::sleep,time::Duration};
fn step(engine:&mut Engine,label:&str,action:Action)->Result<(),String>{
    let view=engine.action(action)?;
    println!("{}",serde_json::json!({"step":label,"view":view}));Ok(())
}
fn notes(engine:&mut Engine,slot:u8,values:&[u8],down:bool)->Result<(),String>{
    for n in values {step(engine,"note",Action::Note{token:format!("probe:{n}"),note:*n,velocity:100,slot,pressed:down})?;}Ok(())
}
fn run(engine:&mut Engine,port:String,fresh:bool)->Result<(),String>{
    step(engine,"connect",Action::Connect{port:port.clone(),fresh})?;
    step(engine,"volume",Action::Control{volume:0.5,sustain:false})?;
    for (slot,preset) in library().presets.into_iter().enumerate(){
        step(engine,&format!("load:{}",preset.name),Action::Load{slot:slot as u8,program:preset.program,operators:None})?;
        notes(engine,slot as u8,&[60],true)?;sleep(Duration::from_millis(600));
        step(engine,"sounding",Action::Poll)?;notes(engine,slot as u8,&[60],false)?;
        sleep(Duration::from_millis(250));step(engine,"panic",Action::Panic)?;
    }
    step(engine,"dry",Action::Fx{room:false})?;
    notes(engine,1,&[48,55,60,64,67,72,76,79],true)?;
    for _ in 0..7{step(engine,"eight_voice",Action::Poll)?;sleep(Duration::from_millis(100));}
    let full=serde_json::to_value(engine.view()).map_err(|e|e.to_string())?;
    if full["telemetry"]["active"]!=255 {return Err(format!("eight voices not active: {full}"));}
    // Repeated physical/UI inputs must not allocate another voice or send a packet.
    notes(engine,1,&[60],true)?;
    if serde_json::to_value(engine.view()).unwrap()["packets"]!=full["packets"] {return Err("duplicate UI note sent another packet".into());}
    step(engine,"sustain",Action::Control{volume:0.5,sustain:true})?;
    notes(engine,1,&[48,55,60,64,67,72,76,79],false)?;
    step(engine,"sustained",Action::Poll)?;
    step(engine,"release_sustain",Action::Control{volume:0.5,sustain:false})?;
    sleep(Duration::from_millis(300));step(engine,"panic",Action::Panic)?;
    let mut ops=library().presets[0].operators.clone();ops[5].output=80;
    step(engine,"operator_edit",Action::Load{slot:0,program:4,operators:Some(ops)})?;
    notes(engine,0,&[60,64,67],true)?;sleep(Duration::from_millis(500));notes(engine,0,&[60,64,67],false)?;
    step(engine,"panic",Action::Panic)?;
    step(engine,"restore",Action::Load{slot:0,program:4,operators:None})?;
    step(engine,"room",Action::Fx{room:true})?;
    notes(engine,0,&[60,64,67],true)?;sleep(Duration::from_millis(600));notes(engine,0,&[60,64,67],false)?;
    sleep(Duration::from_millis(400));step(engine,"panic",Action::Panic)?;
    step(engine,"disconnect",Action::Disconnect)?;
    step(engine,"persistent_reconnect",Action::Connect{port,fresh:false})?;
    for _ in 0..7{step(engine,"final",Action::Poll)?;}
    let result=serde_json::to_value(engine.view()).map_err(|e|e.to_string())?;
    let t=&result["telemetry"];
    if t["flags"].as_u64().unwrap_or(0)&31!=17 {return Err(format!("boot/amplifier/fault flags: {t}"));}
    for key in ["underruns","bad_packets","overruns","pcm_dropped","fx_dropped","fx_clips"] {
        if t[key]!=0 {return Err(format!("hardware counter {key} is nonzero: {t}"));}
    }
    println!("{}",serde_json::json!({"result":"PASS","eight_voices":true,"duplicate_suppressed":true,"telemetry":t}));
    step(engine,"disconnect",Action::Disconnect)
}
fn main(){
    let args:Vec<_>=std::env::args().collect();
    let port=args.get(1).expect("voice-probe COM7 [--fresh]").clone();
    let root=PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap()).join("SynthString/voice-engine");
    let mut engine=Engine::new(root);
    if let Err(e)=run(&mut engine,port,args.iter().any(|s|s=="--fresh")){
        eprintln!("FAILED: {e}");let _=engine.action(Action::Panic);std::process::exit(1);
    }
}
