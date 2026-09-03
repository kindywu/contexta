import { expect, test } from "bun:test";
import { pickRandom, siteAdapters } from "../../src/engine/sites";

test("pickRandom: 从列表中随机取一篇", () => {
  const links = [
    { title: "A", url: "https://a.com/1" },
    { title: "B", url: "https://a.com/2" },
  ];
  const picked = pickRandom(links);
  expect(links).toContain(picked);
});

test("pickRandom: 空列表抛出错误", () => {
  expect(() => pickRandom([])).toThrow();
});

test("注册表:chinadaily 实现是同一接口，抓描述正文正常", async () => {
  const site = siteAdapters.chinadaily;
  expect(site.name).toBe("chinadaily");
  const link = {
    title: "Healthy ecosystems buzz with dragonflies",
    url: "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html",
  };
  const article = await site.fetchArticle(link);
  expect(article.title).toBe(link.title);
  expect(article.url).toBe(link.url);
  expect(article.html.length).toBeGreaterThan(100);
  // 正文里不应残留 script/iframe/a 等噪声
  expect(article.html).not.toMatch(/<script|<iframe|<a\b/i);
}, 60_000);

test("注册表:tencent 实现是同一接口，抓描述正文正常", async () => {
  const site = siteAdapters.tencent;
  expect(site.name).toBe("tencent");
  const link = {
    title: "一见·三个角度读懂“紧密的中吉命运共同体”",
    url: "https://news.qq.com/rain/a/20260827A0D4Y700",
  };
  const article = await site.fetchArticle(link);
  expect(article.title).toBe(link.title);
  expect(article.url).toBe(link.url);
  expect(article.html.length).toBeGreaterThan(100);
  expect(article.html).not.toMatch(/<script|<iframe|<a\b/i);
}, 60_000);

test("注册表:tencent UTR 链接（无 rich_media_content）走兜底提取", async () => {
  const site = siteAdapters.tencent;
  const link = {
    title: "台风“沙德尔”在浙江玉环登陆",
    url: "https://news.qq.com/rain/a/UTR2026082718368600",
  };
  const article = await site.fetchArticle(link);
  expect(article.html.length).toBeGreaterThan(100);
  expect(article.html).toContain("台风");
  expect(article.html).not.toMatch(/<script|<iframe|<a\b/i);
}, 60_000);

test("pickRandom: 从统一入口对外公开导出", () => {
  const links = [
    { title: "A", url: "https://a.com/1" },
    { title: "B", url: "https://a.com/2" },
  ];
  expect(links).toContain(pickRandom(links));
});
