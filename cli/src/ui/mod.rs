//! UI Module
//!
//! This module exports the UI components for the Scalegraph CLI:
//!
//! - `app`: Application state and event loop
//! - `views`: Rendering functions for all UI views
//!
//! The UI module provides a complete terminal interface for interacting
//! with the Scalegraph ledger system.

mod app;
mod views;

pub use app::{run_app, App};
