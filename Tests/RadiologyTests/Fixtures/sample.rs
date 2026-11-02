//! Crate docs — 放射線
use std::collections::HashMap;

/// Doc comment
#[derive(Debug, Clone)]
pub struct Scan<T> {
    pub title: String,
    count: usize,
    data: HashMap<String, T>,
}

pub const MAX_SCANS: usize = 10;

pub enum Modality {
    Xray,
    Ct { slices: u32 },
}

pub trait Render {
    fn render(&self) -> String;
}

impl<T> Render for Scan<T> {
    fn render(&self) -> String {
        let label = format!("{}:{}", self.title, self.count);
        if self.count > 0 {
            for _ in 0..self.count {
                println!("{}", label);
            }
        }
        label
    }
}

mod helpers {
    pub fn normalize(value: &str) -> String { value.trim().to_string() }
}

fn main() {
    let scan = Scan { title: "胸部".to_string(), count: 3, data: Default::default() };
    let _ = scan.render();
    let closure = |x: i32| -> i32 { x * 2 };
    println!("{}", closure(MAX_SCANS as i32));
}
