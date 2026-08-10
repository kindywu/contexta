use anyhow::{anyhow, Result};
use std::path::PathBuf;

use crate::dump::{run_dump, SAMPLE_WORDS};

pub enum Command {
    Dump(DumpArgs),
    Sample(DumpArgs),
    Import { file: PathBuf, target_db: PathBuf },
}

pub struct DumpArgs {
    pub all: bool,
    pub words: Option<Vec<String>>,
    pub limit: Option<usize>,
    pub max_samples: usize,
    pub output: Option<PathBuf>,
}

impl Default for DumpArgs {
    fn default() -> Self {
        DumpArgs {
            all: false,
            words: None,
            limit: None,
            max_samples: 10,
            output: None,
        }
    }
}

fn usage() -> String {
    "用法：
  etl dump [--all | --words \"a b c\"] [--limit N] [--max-samples N] [--output <路径>]
  etl sample [--words \"a b c\"] [--limit N] [--max-samples N] [--output <路径>]   # 默认 3 个精选词
  etl import <file.jsonl> [--target-db <路径>]"
        .to_string()
}

pub fn parse(args: &[String]) -> Result<Command> {
    let Some(cmd) = args.first() else {
        return Err(anyhow!("{}", usage()));
    };
    let rest = &args[1..];
    match cmd.as_str() {
        "--help" | "-h" => {
            println!("{}", usage());
            Ok(Command::Dump(DumpArgs::default()))
        }
        "dump" => parse_dump(rest, false),
        "sample" => parse_dump(rest, true),
        "import" => {
            let mut file: Option<PathBuf> = None;
            let mut target_db: Option<PathBuf> = None;
            let mut i = 0;
            while i < rest.len() {
                match rest[i].as_str() {
                    "--target-db" => {
                        i += 1;
                        target_db = Some(PathBuf::from(
                            rest.get(i).ok_or_else(|| anyhow!("--target-db 缺路径"))?,
                        ));
                    }
                    "--help" | "-h" => {
                        println!("{}", usage());
                        return Ok(Command::Import {
                            file: PathBuf::from(""),
                            target_db: PathBuf::from(""),
                        });
                    }
                    s if s.starts_with('-') => return Err(anyhow!("未知参数: {s}")),
                    s => file = Some(PathBuf::from(s)),
                }
                i += 1;
            }
            let file = file.ok_or_else(|| anyhow!("import 需要 <file.jsonl> 参数"))?;
            let target_db = target_db.unwrap_or_else(default_target_db);
            Ok(Command::Import { file, target_db })
        }
        other => Err(anyhow!("未知命令: {other}\n{}", usage())),
    }
}

fn parse_dump(rest: &[String], sample: bool) -> Result<Command> {
    let mut args = DumpArgs::default();
    if sample {
        args.words = Some(SAMPLE_WORDS.iter().map(|s| s.to_string()).collect());
    }
    let mut i = 0;
    while i < rest.len() {
        match rest[i].as_str() {
            "--all" => args.all = true,
            "--words" => {
                i += 1;
                let raw = rest
                    .get(i)
                    .ok_or_else(|| anyhow!("--words 缺单词串"))?;
                args.words = Some(raw.split_whitespace().map(|s| s.to_string()).collect());
            }
            "--limit" => {
                i += 1;
                args.limit = Some(
                    rest.get(i)
                        .ok_or_else(|| anyhow!("--limit 缺数字"))?
                        .parse()
                        .map_err(|_| anyhow!("--limit 需要整数"))?,
                );
            }
            "--max-samples" => {
                i += 1;
                args.max_samples = rest
                    .get(i)
                    .ok_or_else(|| anyhow!("--max-samples 缺数字"))?
                    .parse()
                    .map_err(|_| anyhow!("--max-samples 需要整数"))?;
            }
            "--output" => {
                i += 1;
                args.output = Some(PathBuf::from(
                    rest.get(i).ok_or_else(|| anyhow!("--output 缺路径"))?,
                ));
            }
            "--help" | "-h" => {
                println!("{}", usage());
                return Ok(if sample {
                    Command::Sample(args)
                } else {
                    Command::Dump(args)
                });
            }
            s => return Err(anyhow!("未知参数: {s}")),
        }
        i += 1;
    }
    Ok(if sample {
        Command::Sample(args)
    } else {
        Command::Dump(args)
    })
}

fn default_target_db() -> PathBuf {
    let root = crate::db::find_repo_root().expect("repo root");
    root.join("impl/app/flutter/assets/contexta.db")
}

pub fn run() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match parse(&args)? {
        Command::Dump(a) => run_dump(&a),
        Command::Sample(a) => run_dump(&a),
        Command::Import { file, target_db } => crate::importer::run_import(&file, &target_db),
    }
}
