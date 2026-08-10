use std::process::ExitCode;

fn main() -> ExitCode {
    match etl::cli::run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("❌ {}", e);
            ExitCode::FAILURE
        }
    }
}
