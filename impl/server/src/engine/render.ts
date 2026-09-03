import type { GeneratedArticle } from "./graph/state";


// 简易markdown转义，避免特殊符号破坏语法
function escapeMdText(text: string): string {
  return text.replace(/([\\`*_{}\[\]()#+\-.!>])/g, "\\$1")
}
function escapeMdLinkUrl(url: string): string {
  return url.replace(/[()]/g, (c) => encodeURIComponent(c))
}

export function renderMarkdown(article: GeneratedArticle): string {
  const metaLines: string[] = [
    `<!-- runDate: ${article.runDate} -->`,
    `<!-- difficulty: ${article.difficulty} -->`,
    `<!-- category: ${article.category} -->`,
    `<!-- path: ${article.path} -->`,
    article.sourceUrl ? `<!-- source_url: ${article.sourceUrl} -->` : null,
    `<!-- titleEn: ${article.titleEn} -->`,
    `<!-- titleZh: ${article.titleZh} -->`,
  ].filter(Boolean) as string[]
  const meta = metaLines.join("\n")

  const body = article.paragraphs
    .map((p, i) => {
      const enText = escapeMdText(p.en)
      const zhText = escapeMdText(p.zh)
      return `### Paragraph ${i + 1} (EN)\n${enText}\n\n### Paragraph ${i + 1} (ZH)\n> ${zhText}`
    })
    .join("\n\n")

  const factBlock = article.factSheet
    ? `**事实参考 FactSheet**\n\n\`\`\`json\n${JSON.stringify(article.factSheet, null, 2)}\n\`\`\``
    : ""

  const sourceBlock = article.sourceUrl
    ? `来源: [原文链接](${escapeMdLinkUrl(article.sourceUrl)})`
    : ""

  const outputParts = [
    meta, // ✅ 补上之前漏掉的元注释
    `# ${escapeMdText(article.titleEn)}`,
    `## ${escapeMdText(article.titleZh)}`,
    `> 难度: ${escapeMdText(article.difficulty)} · 类别: ${escapeMdText(article.category)} · 路径: ${escapeMdText(article.path)}`,
    `---`,
    body,
    `---`,
    factBlock,
    sourceBlock,
  ].filter(Boolean)

  return outputParts.join("\n\n")
}
