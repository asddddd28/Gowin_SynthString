use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    time::Instant,
};
#[derive(Clone)]
pub struct LiveEdit {
    pub index: usize,
    pub profile: Value,
    pub restore: bool,
}
pub struct LiveState {
    pub enabled: bool,
    pub pending: BTreeMap<usize, LiveEdit>,
    pub inflight: Option<LiveEdit>,
    pub applied: BTreeMap<usize, Value>,
    pub last_send: Instant,
    pub error: String,
}
impl Default for LiveState {
    fn default() -> Self {
        Self {
            enabled: false,
            pending: BTreeMap::new(),
            inflight: None,
            applied: BTreeMap::new(),
            last_send: Instant::now() - std::time::Duration::from_secs(1),
            error: String::new(),
        }
    }
}
impl LiveState {
    pub fn state(&self) -> Value {
        json!({"enabled":self.enabled,"pending":self.pending.keys().collect::<Vec<_>>(),"inflight":self.inflight.as_ref().map(|e|e.index),"applied":self.applied,"error":self.error})
    }
    pub fn forget(&mut self, index: usize) {
        self.pending.remove(&index);
        self.applied.remove(&index);
    }
}
pub struct Performance {
    pub transpose: i32,
    pub velocity: Option<u8>,
    pub armed: bool,
    pub channel: u8,
    pub pedals: BTreeSet<String>,
    pub routes: BTreeMap<(u8, u8), usize>,
    pub volume: f64,
    pub pending_volume: Option<f64>,
    pub last_volume_send: Instant,
}
impl Performance {
    pub fn new(volume: f64) -> Self {
        Self {
            transpose: 0,
            velocity: None,
            armed: true,
            channel: 0,
            pedals: BTreeSet::new(),
            routes: BTreeMap::new(),
            volume,
            pending_volume: None,
            last_volume_send: Instant::now(),
        }
    }
    pub fn clear_notes(&mut self) {
        self.pedals.clear();
        self.routes.clear();
    }
    pub fn sustain(&self, owner: &str) -> bool {
        self.pedals.contains("ui")
            || owner
                .strip_prefix("midi:")
                .and_then(|s| s.split(':').next())
                .is_some_and(|c| self.pedals.contains(&format!("midi:{c}")))
    }
    pub fn state(&self) -> Value {
        json!({"transpose":self.transpose,"velocity":self.velocity,"armed":self.armed,"channel":self.channel,"sustain":!self.pedals.is_empty(),"ui_sustain":self.pedals.contains("ui"),"volume":self.volume})
    }
}
pub fn valid_owner(owner: &str) -> bool {
    ["mouse", "keyboard", "audition"].contains(&owner)
        || owner.strip_prefix("pointer:").is_some_and(|id| {
            !id.is_empty() && id.len() <= 10 && id.bytes().all(|b| b.is_ascii_digit())
        })
}
pub fn normalized(mut profile: Value) -> Value {
    if let Some(p) = profile.as_object_mut() {
        p.entry("frame_position").or_insert(json!(0));
    }
    profile
}
