import { describe, expect, test } from "bun:test";
import { badRequest, ok, errorBody, quotaExceeded } from "../src/response";

describe("response", () => {
  test("ok envelope", () => {
    expect(ok({ a: 1 })).toEqual({ code: 0, data: { a: 1 } });
  });
  test("badRequest 映射", () => {
    const e = badRequest("empty word");
    expect(e.status).toBe(400);
    expect(errorBody(e)).toEqual({ code: 400, message: "empty word", error_code: "BAD_PARAM" });
  });
  test("quotaExceeded 映射", () => {
    const e = quotaExceeded("quota");
    expect(e.status).toBe(400);
    expect(e.code).toBe(40001);
    expect(e.errorCode).toBe("QUOTA_EXCEEDED");
  });
});
