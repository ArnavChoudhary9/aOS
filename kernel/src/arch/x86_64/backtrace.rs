//! Frame-pointer stack walking.
//!
//! Every target crate is built with `-C force-frame-pointers=yes`, so each
//! function's frame starts with `push rbp; mov rbp, rsp`. That makes the
//! frames a linked list on the stack:
//!
//! ```text
//!   [rbp]     = caller's saved rbp   (the next link)
//!   [rbp + 8] = return address into the caller
//! ```

use super::cpu;

/// Stop after this many frames, even if the chain continues.
pub const MAX_FRAMES: usize = 32;
/// A frame pointer more than this far above the first one is treated as
/// garbage (Limine's boot stack is 64 KiB; kernel stacks will be 16 KiB).
const MAX_STACK_SPAN: u64 = 1024 * 1024;
/// Lowest canonical higher-half address; all kernel stacks live above it.
const HIGHER_HALF: u64 = 0xffff_8000_0000_0000;

unsafe extern "C" {
    static __text_start: u8;
    static __text_end: u8;
}

/// Walk the caller's stack, calling `f(index, return_address - 1)` for each
/// frame whose return address points into kernel text. Returns the number
/// of frames reported.
///
/// Addresses are reported minus one so they symbolize to the `call`
/// instruction rather than whatever follows it.
#[inline(never)]
pub fn walk(mut f: impl FnMut(usize, u64)) -> usize {
    let text_start = &raw const __text_start as u64;
    let text_end = &raw const __text_end as u64;
    let first = cpu::frame_pointer();
    let mut rbp = first;
    let mut count = 0;

    while count < MAX_FRAMES {
        let plausible = rbp >= HIGHER_HALF
            && rbp.is_multiple_of(8)
            && rbp >= first
            && rbp - first <= MAX_STACK_SPAN
            && rbp.checked_add(16).is_some();
        if !plausible {
            break;
        }
        // SAFETY: `rbp` is 8-aligned, in the higher half and within 1 MiB
        // above a frame pointer we are currently running on, so it points
        // into the mapped boot stack. Reads are volatile because the
        // compiler cannot know this memory is a stack frame.
        let (next, ret) = unsafe {
            (
                core::ptr::read_volatile(rbp as *const u64),
                core::ptr::read_volatile((rbp + 8) as *const u64),
            )
        };
        if ret < text_start || ret >= text_end {
            break;
        }
        f(count, ret - 1);
        count += 1;
        if next <= rbp {
            break;
        }
        rbp = next;
    }
    count
}
