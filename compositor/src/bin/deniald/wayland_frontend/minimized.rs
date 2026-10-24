//! How often a minimized window may draw, and what Denial shows meanwhile.
//!
//! On the phone a minimized window gets no frame callbacks: it is paused, and
//! Denial keeps showing its last frame. Some clients draw a transparent
//! buffer once they are suspended; that frame never reaches the scene. The
//! callbacks a paused window asks for are parked and sent once it is
//! restored, and the kept frame stays until the restored window shows a new
//! one. The desktop shell lets minimized windows draw at the output's rate.

use std::collections::HashSet;

use smithay::reexports::wayland_server::Resource;
use smithay::reexports::wayland_server::backend::ObjectId;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;

use super::WaylandFrontend;

/// How often a window gets frame callbacks. Per-app rates for minimized
/// windows go here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FramePace {
    /// Every output frame it is on.
    Output,
    /// None until it is restored.
    Paused,
}

#[derive(Debug, Default)]
pub(super) struct MinimizedWindows {
    /// Paused windows that asked for a frame callback.
    parked: HashSet<ObjectId>,
    /// Restored windows still showing their kept frame.
    thawing: HashSet<ObjectId>,
    /// The textures of frozen windows in the scene last built: they keep
    /// their frame without being given a new one.
    kept_textures: Vec<u64>,
}

impl WaylandFrontend {
    fn frame_pace(&self, root: &ObjectId) -> FramePace {
        if self.mobile_shell && self.surface_is_minimized(root) {
            FramePace::Paused
        } else {
            FramePace::Output
        }
    }

    /// Queues the frame callbacks of the window rooted at `root` for the next
    /// output frame, or parks them while the window is paused.
    pub(super) fn queue_window_frame_callbacks(&mut self, root: ObjectId) {
        match self.frame_pace(&root) {
            FramePace::Output => {
                self.pending_frame_callback_windows.insert(root);
            }
            FramePace::Paused => {
                self.minimized_windows.parked.insert(root);
            }
        }
    }

    /// Follows the window rooted at `root` being minimized or restored.
    pub(super) fn minimized_changed(&mut self, root: &ObjectId, minimized: bool) {
        if !self.mobile_shell {
            return;
        }
        if minimized {
            self.minimized_windows.thawing.remove(root);
            if self.pending_frame_callback_windows.remove(root) {
                self.minimized_windows.parked.insert(root.clone());
            }
        } else {
            self.minimized_windows.thawing.insert(root.clone());
            if self.minimized_windows.parked.remove(root) {
                self.pending_frame_callback_windows.insert(root.clone());
            }
        }
    }

    #[cfg(feature = "flutter")]
    pub(crate) fn mobile_shell(&self) -> bool {
        self.mobile_shell
    }

    /// Whether the window rooted at `root` shows its kept frame instead of
    /// its committed buffers.
    pub(super) fn window_frozen(&self, root: &ObjectId) -> bool {
        self.mobile_shell
            && (self.surface_is_minimized(root) || self.minimized_windows.thawing.contains(root))
    }

    /// A surface committed new content: a restored window it belongs to
    /// shows its buffers again from this commit on.
    pub(super) fn thaw_on_visual_commit(&mut self, surface: &WlSurface) {
        if self.minimized_windows.thawing.is_empty() {
            return;
        }
        let Some(root) = self.owning_toplevel_surface(surface) else {
            return;
        };
        if !self.surface_is_minimized(&root.id()) {
            self.minimized_windows.thawing.remove(&root.id());
        }
    }

    pub(super) fn clear_kept_textures(&mut self) {
        self.minimized_windows.kept_textures.clear();
    }

    pub(super) fn keep_texture(&mut self, texture_id: u64) {
        self.minimized_windows.kept_textures.push(texture_id);
    }

    /// The textures of frozen windows in the scene last built.
    pub fn kept_texture_ids(&self) -> &[u64] {
        &self.minimized_windows.kept_textures
    }

    pub(super) fn forget_minimized_window(&mut self, root: &ObjectId) {
        self.minimized_windows.parked.remove(root);
        self.minimized_windows.thawing.remove(root);
    }
}
