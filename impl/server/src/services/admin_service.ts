import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { unauthorized } from "../response";
import { issueAdminToken } from "../jwt";

/** Task 8 前只含 login；其余端点（用户列表/封禁/配额/用量/文章审核……）后续增补。 */
export const adminService = {
  login(db: Database, cfg: ServerConfig, username: string, password: string): string {
    const row = db
      .query("SELECT password_hash FROM admin_user WHERE username = ?")
      .get(username) as { password_hash: string } | undefined;
    if (!row) throw unauthorized("TOKEN_EXPIRED");
    let valid = false;
    try {
      valid = Bun.password.verifySync(password, row.password_hash);
    } catch {
      valid = false;
    }
    if (!valid) throw unauthorized("TOKEN_EXPIRED");
    return issueAdminToken(cfg, username);
  },
};
