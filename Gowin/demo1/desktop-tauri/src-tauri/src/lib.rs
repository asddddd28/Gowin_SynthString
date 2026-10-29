//! Native application backend. No interpreter, child process or frontend dependency.
pub mod engine;
pub mod midi;
pub mod model;
pub mod performance;
#[cfg(test)]
mod performance_tests;
pub mod protocol;
pub mod resources;
pub mod runtime;
pub mod surge;
pub mod transport;

pub type Result<T> = std::result::Result<T, String>;
#[cfg(test)]
mod tests;
