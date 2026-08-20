pub mod admin_service;
pub mod article_service;
pub mod auth_service;
pub mod llm_service;
pub mod prompt_service;
pub mod source_service;

use chrono::{Local, TimeZone};

/// 今日零点（服务器本地时区——部署于 Asia/Shanghai，即上海语义）的 Unix 毫秒时间戳。
/// 注意不能用 `NaiveDateTime::and_utc()`（会把本地零点误当 UTC 零点，差 8 小时）；
/// 必须经 `Local.from_local_datetime` 应用时区偏移。T7 查词配额 / T8 每日任务 / T11 用量统计复用。
pub fn today_start_millis() -> i64 {
    let now = Local::now();
    let midnight = now.date_naive().and_hms_opt(0, 0, 0).unwrap();
    Local
        .from_local_datetime(&midnight)
        .earliest()
        .unwrap()
        .timestamp_millis()
}
