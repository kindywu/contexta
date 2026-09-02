import { Database } from "bun:sqlite";
import {
  BaseCheckpointSaver,
  WRITES_IDX_MAP,
  copyCheckpoint,
  getCheckpointId,
} from "@langchain/langgraph-checkpoint";
import type {
  ChannelVersions,
  Checkpoint,
  CheckpointListOptions,
  CheckpointMetadata,
  CheckpointTuple,
  PendingWrite,
} from "@langchain/langgraph-checkpoint";
import type { RunnableConfig } from "@langchain/core/runnables";

/**
 * 基于 Bun 内置 sqlite（bun:sqlite）的 Checkpointer。
 *
 * 为什么不用官方 @langchain/langgraph-checkpoint-sqlite：其底层是
 * better-sqlite3（原生模块），Bun 的兼容 shim 缺 `pragma` 等 API
 * （实测构造即抛 "this.db.pragma is not a function"），故自写一份
 * Bun 原生实现的 BaseCheckpointSaver。
 *
 * 语义对齐官方 MemorySaver（见 langgraph-checkpoint/dist/memory.js）：
 * 每个 superstep 落一条 checkpoint 记录（含序列化的 state），节点中间
 * 写入单独放 writes 表；恢复时按 (thread_id, checkpoint_ns) 取最新
 * checkpoint + 其 pendingWrites 重建状态。
 *
 * 存储为独立文件（默认 data/langgraph.sqlite），与业务库
 * data/pipeline.sqlite 无关。
 */
export class BunSqliteCheckpointer extends BaseCheckpointSaver {
  private readonly db: Database;

  constructor(path: string) {
    super();
    this.db = new Database(path, { create: true });
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS checkpoints (
        thread_id TEXT NOT NULL,
        checkpoint_ns TEXT NOT NULL DEFAULT '',
        checkpoint_id TEXT NOT NULL,
        checkpoint_type TEXT NOT NULL,
        checkpoint BLOB NOT NULL,
        metadata_type TEXT NOT NULL,
        metadata BLOB NOT NULL,
        parent_checkpoint_id TEXT,
        PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id)
      );
      CREATE TABLE IF NOT EXISTS writes (
        thread_id TEXT NOT NULL,
        checkpoint_ns TEXT NOT NULL DEFAULT '',
        checkpoint_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        idx INTEGER NOT NULL,
        channel TEXT NOT NULL,
        value_type TEXT NOT NULL,
        value BLOB NOT NULL,
        PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id, task_id, idx)
      );
    `);
  }

  /** 从一行 checkpoints 记录（含其 pendingWrites）构造 CheckpointTuple。 */
  private async toTuple(row: {
    thread_id: string;
    checkpoint_ns: string;
    checkpoint_id: string;
    checkpoint_type: string;
    checkpoint: Uint8Array;
    metadata_type: string;
    metadata: Uint8Array;
    parent_checkpoint_id: string | null;
  }): Promise<CheckpointTuple> {
    const checkpoint = await this.serde.loadsTyped(
      row.checkpoint_type,
      row.checkpoint,
    );
    const metadata = await this.serde.loadsTyped(row.metadata_type, row.metadata);
    const writes = this.db
      .query(
        `SELECT task_id, channel, value_type, value FROM writes
         WHERE thread_id = ? AND checkpoint_ns = ? AND checkpoint_id = ?
         ORDER BY task_id ASC, idx ASC`,
      )
      .all(row.thread_id, row.checkpoint_ns, row.checkpoint_id) as Array<{
      task_id: string;
      channel: string;
      value_type: string;
      value: Uint8Array;
    }>;
    const pendingWrites = await Promise.all(
      writes.map(async (w) => [
        w.task_id,
        w.channel,
        await this.serde.loadsTyped(w.value_type, w.value),
      ] as [string, string, unknown]),
    );
    const tuple: CheckpointTuple = {
      config: {
        configurable: {
          thread_id: row.thread_id,
          checkpoint_ns: row.checkpoint_ns,
          checkpoint_id: row.checkpoint_id,
        },
      },
      checkpoint,
      metadata,
      pendingWrites,
    };
    if (row.parent_checkpoint_id) {
      tuple.parentConfig = {
        configurable: {
          thread_id: row.thread_id,
          checkpoint_ns: row.checkpoint_ns,
          checkpoint_id: row.parent_checkpoint_id,
        },
      };
    }
    return tuple;
  }

  async getTuple(config: RunnableConfig): Promise<CheckpointTuple | undefined> {
    const threadId = config.configurable?.thread_id;
    const checkpointNs = config.configurable?.checkpoint_ns ?? "";
    const checkpointId = getCheckpointId(config);
    if (threadId === undefined) return undefined;

    const row = checkpointId
      ? this.db
          .query(
            `SELECT * FROM checkpoints
             WHERE thread_id = ? AND checkpoint_ns = ? AND checkpoint_id = ?
             LIMIT 1`,
          )
          .get(threadId, checkpointNs, checkpointId)
      : this.db
          .query(
            `SELECT * FROM checkpoints
             WHERE thread_id = ? AND checkpoint_ns = ?
             ORDER BY checkpoint_id DESC LIMIT 1`,
          )
          .get(threadId, checkpointNs);
    return row ? this.toTuple(row as Parameters<typeof this.toTuple>[0]) : undefined;
  }

  async *list(
    config: RunnableConfig,
    options?: CheckpointListOptions,
  ): AsyncGenerator<CheckpointTuple> {
    const { before, limit, filter } = options ?? {};
    const threadId = config.configurable?.thread_id;
    const checkpointNs = config.configurable?.checkpoint_ns;
    const checkpointId = config.configurable?.checkpoint_id;

    let rows: unknown[];
    if (threadId !== undefined && checkpointNs !== undefined) {
      rows = this.db
        .query(
          `SELECT * FROM checkpoints
           WHERE thread_id = ? AND checkpoint_ns = ?
           ORDER BY checkpoint_id DESC`,
        )
        .all(threadId, checkpointNs);
    } else if (threadId !== undefined) {
      rows = this.db
        .query(
          `SELECT * FROM checkpoints WHERE thread_id = ? ORDER BY checkpoint_id DESC`,
        )
        .all(threadId);
    } else {
      rows = this.db
        .query(`SELECT * FROM checkpoints ORDER BY checkpoint_id DESC`)
        .all();
    }

    let remaining = limit;
    for (const r of rows as Parameters<typeof this.toTuple>[0][]) {
      if (checkpointId && r.checkpoint_id !== checkpointId) continue;
      if (before?.configurable?.checkpoint_id && r.checkpoint_id >= before.configurable.checkpoint_id) continue;
      const metadata = await this.serde.loadsTyped(
        r.metadata_type,
        r.metadata,
      ) as CheckpointMetadata;
      if (filter && !Object.entries(filter).every(([k, v]) => (metadata as Record<string, unknown>)[k] === v)) continue;
      if (remaining !== undefined) {
        if (remaining <= 0) break;
        remaining -= 1;
      }
      yield this.toTuple(r);
    }
  }

  async put(
    config: RunnableConfig,
    checkpoint: Checkpoint,
    metadata: CheckpointMetadata,
    _newVersions?: ChannelVersions,
  ): Promise<RunnableConfig> {
    const threadId = config.configurable?.thread_id;
    if (threadId === undefined) {
      throw new Error(
        "Failed to put checkpoint. The passed RunnableConfig is missing a required \"thread_id\" field in its \"configurable\" property.",
      );
    }
    const checkpointNs = config.configurable?.checkpoint_ns ?? "";
    const prepared = copyCheckpoint(checkpoint);
    const [checkpointType, checkpointData] = await this.serde.dumpsTyped(prepared);
    const [metadataType, metadataData] = await this.serde.dumpsTyped(metadata);
    this.db
      .query(
        `INSERT INTO checkpoints
           (thread_id, checkpoint_ns, checkpoint_id, checkpoint_type, checkpoint,
            metadata_type, metadata, parent_checkpoint_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(thread_id, checkpoint_ns, checkpoint_id)
         DO UPDATE SET checkpoint_type = excluded.checkpoint_type,
                       checkpoint = excluded.checkpoint,
                       metadata_type = excluded.metadata_type,
                       metadata = excluded.metadata,
                       parent_checkpoint_id = excluded.parent_checkpoint_id`,
      )
      .run(
        threadId,
        checkpointNs,
        checkpoint.id,
        checkpointType,
        checkpointData,
        metadataType,
        metadataData,
        config.configurable?.checkpoint_id ?? null,
      );
    return {
      configurable: {
        thread_id: threadId,
        checkpoint_ns: checkpointNs,
        checkpoint_id: checkpoint.id,
      },
    };
  }

  async putWrites(
    config: RunnableConfig,
    writes: PendingWrite[],
    taskId: string,
  ): Promise<void> {
    const threadId = config.configurable?.thread_id;
    const checkpointNs = config.configurable?.checkpoint_ns ?? "";
    const checkpointId = config.configurable?.checkpoint_id;
    if (threadId === undefined || checkpointId === undefined) {
      throw new Error(
        "Failed to put writes. The passed RunnableConfig is missing required \"thread_id\" / \"checkpoint_id\" fields.",
      );
    }
    const stmt = this.db.query(
      `INSERT OR IGNORE INTO writes
         (thread_id, checkpoint_ns, checkpoint_id, task_id, idx, channel, value_type, value)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    for (const [channel, value] of writes) {
      const idx = WRITES_IDX_MAP[channel] ?? 0;
      const [valueType, valueData] = await this.serde.dumpsTyped(value);
      stmt.run(threadId, checkpointNs, checkpointId, taskId, idx, channel, valueType, valueData);
    }
  }

  async deleteThread(threadId: string): Promise<void> {
    this.db.query(`DELETE FROM checkpoints WHERE thread_id = ?`).run(threadId);
    this.db.query(`DELETE FROM writes WHERE thread_id = ?`).run(threadId);
  }

  /**
   * 删除某日全部线程的检查点（thread_id 前缀 `daily-<runDate>-`，新旧格式
   * daily-<date>-<slot> 与历史 daily-<date>-<slot>-<attempt> 一并命中）。
   * 供 delete-daily 会同业务库清空当日数据；返回 checkpoints/writes 删除行数。
   */
  deleteThreadsByDate(runDate: string): { checkpoints: number; writes: number } {
    const like = `daily-${runDate}-%`;
    const writes = this.db.query(`DELETE FROM writes WHERE thread_id LIKE ?`).run(like).changes;
    const checkpoints = this.db.query(`DELETE FROM checkpoints WHERE thread_id LIKE ?`).run(like).changes;
    return { checkpoints, writes };
  }
}
