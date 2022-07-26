#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: (parity_db::Options, &[u8])| {
	let (options, data) = data;

	if !options.is_valid() {
		return
	}

	let _ = parity_db::Options::load_fuzzed_metadata(data);
});
