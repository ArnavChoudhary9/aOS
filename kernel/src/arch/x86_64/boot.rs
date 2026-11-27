//! Limine boot protocol: requests and the kernel entry point.
//!
//! Limine scans the image for these statics between the start and end
//! markers, fills in their responses, then jumps to [`kmain`] in 64-bit long
//! mode with interrupts disabled and its own page tables and stack.

use limine::BaseRevision;
use limine::request::{
    ExecutableAddressRequest, ExecutableCmdlineRequest, FramebufferRequest, HhdmRequest,
    MemoryMapRequest, ModuleRequest, RequestsEndMarker, RequestsStartMarker, RsdpRequest,
};

#[used]
#[unsafe(link_section = ".requests_start_marker")]
static REQUESTS_START: RequestsStartMarker = RequestsStartMarker::new();

/// Base revision 3: the newest the stable-compatible `limine` 0.5.0 crate speaks.
#[used]
#[unsafe(link_section = ".requests")]
static BASE_REVISION: BaseRevision = BaseRevision::with_revision(3);

#[used]
#[unsafe(link_section = ".requests")]
static HHDM: HhdmRequest = HhdmRequest::new();

#[used]
#[unsafe(link_section = ".requests")]
static MEMMAP: MemoryMapRequest = MemoryMapRequest::new();

#[used]
#[unsafe(link_section = ".requests")]
static EXECUTABLE_ADDRESS: ExecutableAddressRequest = ExecutableAddressRequest::new();

#[used]
#[unsafe(link_section = ".requests")]
static MODULES: ModuleRequest = ModuleRequest::new();

#[used]
#[unsafe(link_section = ".requests")]
static FRAMEBUFFER: FramebufferRequest = FramebufferRequest::new();

#[used]
#[unsafe(link_section = ".requests")]
static RSDP: RsdpRequest = RsdpRequest::new();

#[used]
#[unsafe(link_section = ".requests")]
static CMDLINE: ExecutableCmdlineRequest = ExecutableCmdlineRequest::new();

#[used]
#[unsafe(link_section = ".requests_end_marker")]
static REQUESTS_END: RequestsEndMarker = RequestsEndMarker::new();

/// What the kernel learned from Limine, copied out of the responses.
pub struct BootInfo {
    pub base_revision_supported: bool,
    pub loaded_revision: u64,
    pub virtual_base: u64,
    pub physical_base: u64,
    pub has_hhdm: bool,
    pub has_memmap: bool,
    pub has_modules: bool,
    pub has_framebuffer: bool,
    pub has_rsdp: bool,
    pub cmdline: &'static str,
}

/// Kernel entry point, named by `ENTRY(kmain)` in `linker.ld`.
#[unsafe(no_mangle)]
extern "C" fn kmain() -> ! {
    let (virtual_base, physical_base) = EXECUTABLE_ADDRESS
        .get_response()
        .map_or((0, 0), |r| (r.virtual_base(), r.physical_base()));

    let info = BootInfo {
        base_revision_supported: BASE_REVISION.is_supported(),
        loaded_revision: BASE_REVISION.loaded_revision().unwrap_or(0),
        virtual_base,
        physical_base,
        has_hhdm: HHDM.get_response().is_some(),
        has_memmap: MEMMAP.get_response().is_some(),
        has_modules: MODULES.get_response().is_some(),
        has_framebuffer: FRAMEBUFFER.get_response().is_some(),
        has_rsdp: RSDP.get_response().is_some(),
        cmdline: CMDLINE
            .get_response()
            .and_then(|r| r.cmdline().to_str().ok())
            .unwrap_or(""),
    };

    crate::kernel_main(info)
}
