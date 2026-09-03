// src/services/article_delivery.ts
// 文章投放（2026-09-03）：账户(phone)×难度 独立游标与已读账本；同日冻结按账号（任意设备）
// 语义（spec §3）：① 同日冻结——已有今日交付则原样返回，不推进游标；
// ② cursor = MAX(article_id) 账本；新文章池 id>cursor 取最新 count 篇；
// 不足按 id ASC 补位「从未交付过」；仍不足返回剩余（不重复已读——空交付不记账，
// ③ 单事务内完成冻结检查+选文+记账——并发同日双请求串行化（SQLite 写锁），
// 后到者命中冻结检查返回首者结果；空交付不记账（同日可再投）。
// 配额：min(count, users.quota_article_daily ?? DEFAULT_ARTICLE_QUOTA_DAILY)。
import type { Database } from "bun:sqlite";
import type { Difficulty } from "../engine/schema";
import { localDate } from "../engine/utils/time";
import { toArticleForApp, type ArticleForApp } from "./article_reader";

export const DEFAULT_ARTICLE_QUOTA_DAILY = 5;

export interface DeliveryArgs {
  phone: string;
  deviceId: string;
  difficulty: Difficulty;
  count: number;
  nowMs: number;
  timeZone: string;
}

export interface DeliveryResult {
  deliveryDate: string;
  articles: ArticleForApp[]; // order_index = 交付内序号 1..N
}

/** approved + 槽位 success 过滤后的文章 id（与旧 listApprovedByDate 同谓词）。 */
function approvedArticleIds(
  db: Database,
  difficulty: string,
  extras: { gt?: number; exclude?: number[]; order: "ASC" | "DESC"; limit: number },
): number[] {
  const notGt = extras.gt !== undefined ? "AND a.id > ?" : "";
  const excludeClause =
    extras.exclude && extras.exclude.length > 0
      ? `AND a.id NOT IN (${extras.exclude.map(() => "?").join(",")})`
      : "";
  const params: (string | number)[] = [difficulty];
  if (extras.gt !== undefined) params.push(extras.gt);
  if (extras.exclude && extras.exclude.length > 0) params.push(...extras.exclude);
  params.push(extras.limit);
  const rows = db
    .query(
      `SELECT a.id FROM articles a
       JOIN batch_slots s ON s.article_id = a.id AND s.status = 'success'
       JOIN article_review r ON r.article_id = a.id AND r.status = 'approved'
       WHERE a.difficulty = ? ${notGt} ${excludeClause}
       ORDER BY a.id ${extras.order} LIMIT ?`,
    )
    .all(...params) as { id: number }[];
  return rows.map((r) => r.id);
}

export function deliverArticles(db: Database, args: DeliveryArgs): DeliveryResult {
  // 空文章（无难度文章可投）快速路径在事务外？——不行：冻结检查必须与记账同快照，
  // 统一在一个事务内（读已提交 + 写串行）。
  const deliveryDate = localDate(args.timeZone, new Date(args.nowMs));
  return db.transaction((): DeliveryResult => {
    // ① 同日冻结（按账号：任意设备当天读都返回同一批）
    const frozen = db
      .query(
        `SELECT article_id FROM article_delivery
         WHERE phone = ? AND difficulty = ? AND delivery_date = ?
         ORDER BY id`,
      )
      .all(args.phone, args.difficulty, deliveryDate) as { article_id: number }[];
    if (frozen.length > 0) {
      return {
        deliveryDate,
        articles: frozen.map((f, i) => toArticleForApp(db, f.article_id, i + 1)),
      };
    }

    // ② 全新交付
    const quotaRow = db
      .query("SELECT quota_article_daily FROM users WHERE phone = ?")
      .get(args.phone) as { quota_article_daily: number | null } | undefined;
    const quota = quotaRow?.quota_article_daily ?? DEFAULT_ARTICLE_QUOTA_DAILY;
    const count = Math.min(args.count, Math.max(quota, 0));

    const delivered = (
      db
        .query(
          `SELECT DISTINCT article_id FROM article_delivery
           WHERE phone = ? AND difficulty = ?`,
        )
        .all(args.phone, args.difficulty) as { article_id: number }[]
    ).map((r) => r.article_id);
    const cursor = delivered.length === 0 ? 0 : Math.max(...delivered);

    const exhausted = [...delivered];
    const chosen: number[] = [];
    // a. 新文章池（id > cursor 最新优先）
    chosen.push(...approvedArticleIds(db, args.difficulty, { gt: cursor, order: "DESC", limit: count }));
    exhausted.push(...chosen);
    // b. 未读补位（最早优先，跳过已交付与已选）——永不重复已读；
    //    不足即返回剩余（可能为空），不追加兜底（用户不读相同文章；空交付不记账，
    //    当天 08:00 生成窗口后再次调用可投到新文章）
    if (chosen.length < count) {
      chosen.push(
        ...approvedArticleIds(db, args.difficulty, {
          exclude: [...new Set(exhausted)], order: "ASC", limit: count - chosen.length,
        }),
      );
    }

    // d. 记账（仅非空交付）。UNIQUE(phone, article_id)：正常路径下补位已排除
    //    全部已交付——插入冲突=算法 bug，用普通 INSERT 让它大声失败（不静默 OR IGNORE）
    if (chosen.length > 0) {
      const now = args.nowMs;
      const ins = db.query(
        `INSERT INTO article_delivery
           (phone, device_id, difficulty, article_id, delivery_date, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      );
      for (const id of chosen) {
        ins.run(args.phone, args.deviceId, args.difficulty, id, deliveryDate, now);
      }
    }

    return {
      deliveryDate,
      articles: chosen.map((id, i) => toArticleForApp(db, id, i + 1)),
    };
  })();
}
