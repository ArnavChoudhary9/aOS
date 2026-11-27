//! Links the kernel with its own linker script. Only applies when building
//! for the bare-metal target, so host tooling (e.g. rust-analyzer) is unaffected.

fn main() {
    let dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR");
    println!("cargo:rerun-if-changed=linker.ld");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("none") {
        println!("cargo:rustc-link-arg-bins=-T{dir}/linker.ld");
    }
}
