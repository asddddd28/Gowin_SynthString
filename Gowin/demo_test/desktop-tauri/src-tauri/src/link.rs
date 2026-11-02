use crate::{
    model::Transfer,
    protocol::{Board, Command},
};
use std::collections::VecDeque;
struct Pending {
    command: Command,
    seq: u8,
    sent: f64,
    tries: u8,
    collisions: u8,
}
#[derive(Default)]
pub struct Link {
    queue: VecDeque<Command>,
    pending: Option<Pending>,
    seq: u8,
    pub view: Transfer,
    label: String,
}
impl Link {
    pub fn start(&mut self, commands: Vec<Command>, label: &str) -> Result<(), String> {
        if self.view.busy {
            return Err("正在等待板卡确认，请稍候".into());
        }
        self.view = Transfer {
            busy: !commands.is_empty(),
            completed: 0,
            total: commands.len(),
            failures: self.view.failures,
            message: format!("{label} · 准备发送"),
        };
        self.label = label.into();
        self.queue = commands.into();
        Ok(())
    }
    fn next_seq(&mut self) -> u8 {
        let n = self.seq;
        self.seq = (u16::from(self.seq) + 1).rem_euclid(255) as u8;
        n
    }
    pub fn fail(&mut self, reason: impl Into<String>) {
        self.queue.clear();
        self.pending = None;
        self.view.busy = false;
        self.view.failures += 1;
        self.view.message = reason.into();
    }
    pub fn ack(&mut self, b: &Board) {
        let Some(p) = &self.pending else { return };
        if b.result == 0x80 || b.seq != p.seq {
            return;
        }
        if b.result == 7 && p.collisions < 2 {
            let seq = self.next_seq();
            let p = self.pending.as_mut().unwrap();
            p.seq = seq;
            p.collisions += 1;
            p.tries = 0;
            p.sent = -100.;
            return;
        }
        if b.result != 0 {
            self.fail(format!(
                "板卡拒绝：{}",
                match b.result {
                    1 => "CRC 错误",
                    2 => "没有暂存事务",
                    3 => "范围或阈值无效",
                    4 => "32 键配置不完整",
                    6 => "命令不支持",
                    7 => "序号冲突",
                    _ => "未知错误",
                }
            ));
            return;
        }
        self.pending = None;
        self.view.completed += 1;
        self.view.busy = !self.queue.is_empty();
        self.view.message = format!(
            "{} · 已确认 {}/{}",
            self.label, self.view.completed, self.view.total
        );
    }
    pub fn tick(&mut self, now: f64) -> Option<Vec<u8>> {
        if let Some(p) = &mut self.pending {
            if now - p.sent < 1. {
                return None;
            }
            if p.tries >= 3 {
                self.fail("板卡确认超时；未确认下发成功");
                return None;
            }
            p.tries += 1;
            p.sent = now;
            return Some(p.command.encode(p.seq));
        }
        if let Some(command) = self.queue.pop_front() {
            let seq = self.next_seq();
            let bytes = command.encode(seq);
            self.pending = Some(Pending {
                command,
                seq,
                sent: now,
                tries: 1,
                collisions: 0,
            });
            return Some(bytes);
        }
        None
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn status(seq: u8, result: u8) -> Board {
        Board {
            seq,
            result,
            configured: false,
            mode: 0,
            direction: 0,
            generation: 0,
            pressed: 0,
        }
    }
    #[test]
    fn matching_ack_only_and_retry() {
        let mut l = Link::default();
        l.start(vec![Command::new(0x30)], "query").unwrap();
        let first = l.tick(0.).unwrap();
        l.ack(&status(12, 0));
        l.ack(&status(0, 0x80));
        assert!(l.view.busy);
        assert_eq!(l.tick(1.1).unwrap(), first);
        l.ack(&status(0, 0));
        assert!(!l.view.busy);
        assert_eq!(l.view.completed, 1);
    }
    #[test]
    fn collision_changes_sequence_and_timeout_fails() {
        let mut l = Link::default();
        l.start(vec![Command::new(0x30)], "query").unwrap();
        l.tick(0.);
        l.ack(&status(0, 7));
        assert!(String::from_utf8(l.tick(0.1).unwrap())
            .unwrap()
            .starts_with("!01"));
        l.tick(1.2);
        l.tick(2.3);
        l.tick(3.4);
        assert_eq!(l.view.failures, 1);
        assert!(!l.view.busy);
    }
}
