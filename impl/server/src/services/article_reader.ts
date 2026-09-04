// src/services/article_reader.ts
// 文章投放读取映射（pipeline 库）：按文章 id 取出数据并映射为 App 契约字段。
// 选文逻辑（冻结/游标/未读补位/配额）在 article_delivery.ts；本文件只做单篇映射。
// 响应键名精确 snake_case（App DTO article_dto.dart fromJson 按此解析）：
// {id, target_date, difficulty, content_category, order_index, title, status,
//  regenerate_count, paragraphs: [{order_index, english_text, chinese_translation}]}
// 派生规则：regenerate_count = 该槽位累计 rejected 数（补生成的历史行保留）；
// 段落 order_index = paragraph_index + 1；status 恒为 'SUCCESS'。
// source_url 属服务端内部审计字段，绝不下发（App 契约不含）。
import type { Database } from "bun:sqlite";

export interface ArticleParagraphForApp {
  order_index: number;
  english_text: string;
  chinese_translation: string;
}

export interface ArticleForApp {
  id: number;
  target_date: string;
  difficulty: string;
  content_category: string;
  order_index: number;
  title: string;
  status: string;
  regenerate_count: number;
  paragraphs: ArticleParagraphForApp[];
}

/** 单篇文章 → App 契约（段落查询 + snake_case 映射）；orderIndex 由调用方给定。
 *  regenerate_count 语义：该文章所在槽位的 rejected 审核行数（reRun 后槽位指向
 *  新文章，regenerate_count = 槽位 rejected 历史）。 */
export function toArticleForApp(
  db: Database,
  articleId: number,
  orderIndex: number,
): ArticleForApp {
  const row = db
    .query("SELECT id, run_date, difficulty, category, title_en FROM articles WHERE id = ?")
    .get(articleId) as {
    id: number; run_date: string; difficulty: string;
    category: string; title_en: string;
  };
  const regen = db
    .query(
      `SELECT COUNT(*) AS n FROM article_review rr
       JOIN batch_slots s ON s.id = rr.slot_id
       WHERE s.article_id = ? AND rr.status = 'rejected'`,
    )
    .get(articleId) as { n: number };
  const paras = db
    .query("SELECT paragraph_index, text_en, text_zh FROM article_paragraphs WHERE article_id = ? ORDER BY paragraph_index")
    .all(articleId) as { paragraph_index: number; text_en: string; text_zh: string }[];
  return {
    id: row.id,
    target_date: row.run_date,
    difficulty: row.difficulty,
    content_category: row.category,
    order_index: orderIndex,
    title: row.title_en,
    status: "SUCCESS",
    regenerate_count: regen.n,
    paragraphs: paras.map((p) => ({
      order_index: p.paragraph_index + 1,
      english_text: p.text_en,
      chinese_translation: p.text_zh,
    })),
  };
}
