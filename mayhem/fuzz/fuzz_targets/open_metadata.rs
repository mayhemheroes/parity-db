//! Fuzz parity-db's metadata-file parser (`Options::load_metadata_file`).
//!
//! Port of the original `open-metadata` target: upstream removed the
//! `arbitrary` feature and `load_fuzzed_metadata`, so the same code path
//! (parsing an on-disk `metadata` file) is now driven by writing the fuzz
//! input to a temp file and loading it through the public API.

#![no_main]
use libfuzzer_sys::fuzz_target;
use std::io::Write;

fuzz_target!(|data: &[u8]| {
	let dir = tempfile::tempdir().expect("tempdir");
	let path = dir.path().join("metadata");
	{
		let mut f = std::fs::File::create(&path).expect("create metadata file");
		f.write_all(data).expect("write metadata file");
	}
	let _ = parity_db::Options::load_metadata_file(&path);
});
