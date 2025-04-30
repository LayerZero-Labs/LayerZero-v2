fn main() {
    println!("cargo:rerun-if-env-changed=EXECUTOR_ID");
}
