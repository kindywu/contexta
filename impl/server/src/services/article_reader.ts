// src/services/article_reader.ts
// 文章下发读取（pipeline 库）：approved 过滤 + App 契约字段映射。
// 响应键名精确 snake_case（App DTO article_dto.dart fromJson 按此解析）：
// {id, target_date, difficulty, content_category, order_index, title, status,
//  regenerate_count, paragraphs: [{order_index, english_text, chinese_translation}]}
// 派生规则：order_index = 同难度槽位 1 起序号（slot_index - min(slot_index) + 1）；
// regenerate_count = 该槽位累计 rejected 数（补生成的历史行保留）；
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

/**
 * 某 ISO 日期已过审（approved）且槽位成功（success）的文章，按难度字典序 + 槽位序号排序。
 * 槽位成功过滤：writeSlotResult 的 article_id = COALESCE(?, article_id) 从不清空，
 * reRun 失败会残留旧 approved 文章 —— 仅下发 success 槽位的最新文章。
 * 任意字符串 date 均安全：无匹配行即返回空（对齐旧版"非法日期 200 空结果"）。
 */
export function listApprovedByDate(db: Database, date: string): ArticleForApp[] {
  const rows = db.query(`
    SELECT a.id, a.run_date, a.difficulty, a.category, a.title_en,
           s.slot_index,
           (s.slot_index - m.min_slot + 1) AS order_index,
           (SELECT COUNT(*) FROM article_review rr
             WHERE rr.slot_id = s.id AND rr.status = 'rejected') AS regen_count
    FROM batch_slots s
    JOIN articles a ON a.id = s.article_id
    JOIN article_review r ON r.article_id = a.id AND r.status = 'approved'
    JOIN (SELECT run_date, difficulty, MIN(slot_index) AS min_slot
          FROM batch_slots WHERE run_date = ? GROUP BY run_date, difficulty) m
      ON m.run_date = s.run_date AND m.difficulty = s.difficulty
    WHERE a.run_date = ?
      AND s.status = 'success'
    ORDER BY a.difficulty, order_index
  `).all(date, date) as {
    id: number;
    run_date: string;
    difficulty: string;
    category: string;
    title_en: string;
    slot_index: number;
    order_index: number;
    regen_count: number;
  }[];

  return rows.map((r) => {
    const paras = db
      .query(
        "SELECT paragraph_index, text_en, text_zh FROM article_paragraphs WHERE article_id = ? ORDER BY paragraph_index",
      )
      .all(r.id) as { paragraph_index: number; text_en: string; text_zh: string }[];
    return {
      id: r.id,
      target_date: r.run_date,
      difficulty: r.difficulty,
      content_category: r.category,
      order_index: r.order_index,
      title: r.title_en,
      status: "SUCCESS",
      regenerate_count: r.regen_count,
      paragraphs: paras.map((p) => ({
        order_index: p.paragraph_index + 1,
        english_text: p.text_en,
        chinese_translation: p.text_zh,
      })),
    };
  });
}
