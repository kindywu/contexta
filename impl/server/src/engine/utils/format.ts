/** 毫秒数格式化成简短耗时文本。 */
export function fmtMs(t: number): string {
  return `${t.toFixed(0)}ms`;
}
