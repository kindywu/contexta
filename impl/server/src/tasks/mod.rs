pub mod article_daily_task;

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

/// 可注入的 sleep 函数（每日任务的等待抽象）：生产用 `tokio::time::sleep`（真实定时器），
/// 测试可注入替身或在暂停的 tokio 虚拟时钟下用 `default_sleep` + `time::advance` 推进。
pub type SleepFn = Arc<dyn Fn(Duration) -> Pin<Box<dyn Future<Output = ()> + Send>> + Send + Sync>;

/// 生产默认 sleep：真实定时器（tokio 时钟暂停时亦可被 `tokio::time::advance` 唤醒）。
pub fn default_sleep() -> SleepFn {
    Arc::new(|d: Duration| -> Pin<Box<dyn Future<Output = ()> + Send>> {
        Box::pin(tokio::time::sleep(d))
    })
}
