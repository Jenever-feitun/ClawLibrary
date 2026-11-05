import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { chromium } from 'playwright';

// Exercise the shipped page styles without starting telemetry or loading game assets.
const html = await fs.readFile(new URL('../index.html', import.meta.url), 'utf8');
const styles = html.match(/<style>([\s\S]*?)<\/style>/)?.[1];
assert.ok(styles, 'Page styles must exist');
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  for (const viewport of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport);
    await page.setContent(`<style>${styles}</style><div id="app"><canvas></canvas></div>`);
    const colors = await page.evaluate(() => {
      const style = (selector) => getComputedStyle(document.querySelector(selector));
      return {
        root: style('html').backgroundColor,
        body: style('body').backgroundColor,
        image: style('body').backgroundImage,
        app: style('#app').backgroundColor,
        canvas: style('canvas').backgroundColor,
        ink: style('body').color,
        muted: style('body').getPropertyValue('--muted').trim()
      };
    });
    assert.equal(colors.root, 'rgb(31, 31, 31)');
    assert.equal(colors.body, 'rgb(31, 31, 31)');
    assert.equal(colors.image, 'none', 'No gradient may obscure the background');
    assert.equal(colors.app, 'rgba(0, 0, 0, 0)');
    assert.equal(colors.canvas, 'rgba(0, 0, 0, 0)');
    for (const color of [colors.ink, colors.muted]) {
      const [r, g, b, alpha = 1] = color.match(/[\d.]+/g).map(Number);
      const luminance = (channels) => channels.map((v) => {
        const s = v / 255;
        return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
      }).reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
      const fg = luminance([r, g, b].map((v) => v * alpha + 31 * (1 - alpha)));
      const bg = luminance([31, 31, 31]);
      assert.ok((fg + 0.05) / (bg + 0.05) >= 4.5, `${color} must meet WCAG AA contrast`);
    }
    console.log(`PASS ${viewport.width}x${viewport.height}: dark gray, transparent game layers, text contrast >= 4.5:1`);
  }
} finally {
  await browser.close();
}
