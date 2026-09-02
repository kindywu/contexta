import { expect, test } from "bun:test";
import type { AnchorSnap } from "../../src/engine/sites/common";
import { extractChinaDailyLinks } from "../../src/engine/sites/chinadaily";
import { extractTencentNewsLinks } from "../../src/engine/sites/tencent";

/** 构造快照的小助手，避免每个 fixture 写全字段。 */
function snap(partial: Partial<AnchorSnap> & { href: string }): AnchorSnap {
  return { text: "", cls: "", childTexts: [], ...partial };
}

test("extractChinaDailyLinks: 按 /a/ 文章 URL 模式提取标题与链接", () => {
  const links = extractChinaDailyLinks([
    snap({
      href: "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html",
      text: "Healthy ecosystems buzz with dragonflies",
    }),
    snap({ href: "https://www.chinadaily.com.cn/china/", text: "Asia-Pacific" }),
  ]);
  expect(links).toEqual([
    {
      title: "Healthy ecosystems buzz with dragonflies",
      url: "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html",
    },
  ]);
});

test("extractChinaDailyLinks: 无标题锚点跳过", () => {
  const links = extractChinaDailyLinks([
    snap({
      href: "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html",
      text: "   ",
    }),
  ]);
  expect(links).toEqual([]);
});

test("extractChinaDailyLinks: 同 URL 只保留首个，且保持顺序", () => {
  const href = "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html";
  const links = extractChinaDailyLinks([
    snap({ href, text: "Title A" }),
    snap({ href, text: "Title A (dupe)" }),
    snap({
      href: "https://www.chinadaily.com.cn/a/202608/27/WS6a8fabd6e4b06d4aa055aba6.html",
      text: "Title B",
    }),
  ]);
  expect(links).toEqual([
    { title: "Title A", url: href },
    {
      title: "Title B",
      url: "https://www.chinadaily.com.cn/a/202608/27/WS6a8fabd6e4b06d4aa055aba6.html",
    },
  ]);
});

test("extractChinaDailyLinks: 跳过超出 30 天的旧栏目标签页", () => {
  const links = extractChinaDailyLinks([
    snap({
      href: "https://www.chinadaily.com.cn/a/202406/14/WS666c012aa31095c51c508ff0.html",
      text: "China Up-close",
    }),
  ]);
  expect(links).toEqual([]);
});

test("extractChinaDailyLinks: 剥离带 query 的额外参数", () => {
  const links = extractChinaDailyLinks([
    snap({
      href: "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html?source=x",
      text: "Title",
    }),
  ]);
  expect(links[0]?.url).toBe(
    "https://www.chinadaily.com.cn/a/202608/28/WS6a90c54ae4b06d4aa055adc6.html",
  );
});

test("extractTencentNewsLinks: a.link-item 直接取锚点文本", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://news.qq.com/rain/a/20260827A0D4Y700",
      cls: "link-item lunbo-link",
      text: "一见·三个角度读懂“紧密的中吉命运共同体”",
    }),
  ]);
  expect(links).toEqual([
    {
      title: "一见·三个角度读懂“紧密的中吉命运共同体”",
      url: "https://news.qq.com/rain/a/20260827A0D4Y700",
    },
  ]);
});

test("extractTencentNewsLinks: a.article-title 标签在前时取 span 标题并去标签", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://news.qq.com/rain/a/UTR2026082215737200",
      cls: "article-title",
      text: "专题专访曝光“甲醛白菜”博主：担心被报复，但总得有人站出来",
      childTexts: [
        "专题",
        "专访曝光“甲醛白菜”博主：担心被报复，但总得有人站出来",
      ],
    }),
  ]);
  expect(links).toEqual([
    {
      title: "专访曝光“甲醛白菜”博主：担心被报复，但总得有人站出来",
      url: "https://news.qq.com/rain/a/UTR2026082215737200",
    },
  ]);
});

test("extractTencentNewsLinks: a.article-title 无标签时取唯一子元素文本", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://news.qq.com/rain/a/20260828A02JUA00",
      cls: "article-title",
      text: "日本跨党派议员团访华，专家：要中方单方面回应不现实",
      childTexts: ["日本跨党派议员团访华，专家：要中方单方面回应不现实"],
    }),
  ]);
  expect(links).toEqual([
    {
      title: "日本跨党派议员团访华，专家：要中方单方面回应不现实",
      url: "https://news.qq.com/rain/a/20260828A02JUA00",
    },
  ]);
});

test("extractTencentNewsLinks: a.article-base-info 取标题子元素，不含来源和时间", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://news.qq.com/rain/a/20260828A0460K00",
      cls: "article-base-info",
      text: "热点精选“中华第一舰”退出现役长安街知事2小时前",
      childTexts: ["热点精选", "“中华第一舰”退出现役", "长安街知事2小时前"],
    }),
  ]);
  expect(links).toEqual([
    {
      title: "“中华第一舰”退出现役",
      url: "https://news.qq.com/rain/a/20260828A0460K00",
    },
  ]);
});

test("extractTencentNewsLinks: 剥掉标题里的实时播报前缀", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://news.qq.com/rain/a/UTR2026082623098700",
      cls: "article-title",
      text: "实时播报尼泊尔北部山洪遇难人数升至469人",
      childTexts: ["实时播报", "尼泊尔北部山洪遇难人数升至469人"],
    }),
  ]);
  expect(links[0]?.title).toBe("尼泊尔北部山洪遇难人数升至469人");
});

test("extractTencentNewsLinks: 图片位锚点（无文字）跳过", () => {
  const links = extractTencentNewsLinks([
    snap({ href: "https://news.qq.com/rain/a/20260828A0460K00", text: "" }),
  ]);
  expect(links).toEqual([]);
});

test("extractTencentNewsLinks: 剥离 adChannelId 等 query 参数", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://news.qq.com/rain/a/20260828A0460K00?adChannelId=news",
      cls: "article-title",
      text: "标题",
      childTexts: ["标题"],
    }),
  ]);
  expect(links[0]?.url).toBe("https://news.qq.com/rain/a/20260828A0460K00");
});

test("extractTencentNewsLinks: 外域链接（非 rain/a/）不截取", () => {
  const links = extractTencentNewsLinks([
    snap({
      href: "https://mp.weixin.qq.com/s/T1q2sJsF9HJlY5w7mCHB9g",
      cls: "article-title",
      text: "外部文章",
      childTexts: ["外部文章"],
    }),
  ]);
  expect(links).toEqual([]);
});

test("extractTencentNewsLinks: 同 URL 去重（base-info 与图片位共存的场景）", () => {
  const href = "https://news.qq.com/rain/a/20260828A0460K00";
  const links = extractTencentNewsLinks([
    snap({
      href,
      cls: "article-title",
      text: "标题",
      childTexts: ["标题"],
    }),
    snap({ href, text: "" }),
  ]);
  expect(links).toEqual([{ title: "标题", url: href }]);
});
