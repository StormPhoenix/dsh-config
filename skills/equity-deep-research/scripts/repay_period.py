#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""回本年限法计算器。

口径：花多少钱买下这家公司，它每年赚的利润多少年能把这笔钱赚回来。
回本即总收益 100%，再按年限折算成年化。

用法示例：
    python repay_period.py --price 20.0 --shares 5.0 --profit 1.50 --growth 0.0 --hurdle 0.096

参数：
    --price   当前股价（元）
    --shares  总股本（亿股）
    --profit  当期年利润（亿元）
    --growth  利润年增速（小数，0 表示零增长）
    --hurdle  门槛回报（小数，默认 0.096 = 9.6%）
              本 skill 全文统一门槛 9.6%（推导口径：无风险利率 + 风险溢价）；
              不得改用 10%、12% 等其他门槛。
"""
import argparse
import math
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def cum_profit(profit0, growth, years):
    """前 years 年累计利润（亿元），支持小数年，末段按比例计。"""
    n_full = int(years)
    cum = 0.0
    p = profit0
    for _ in range(n_full):
        cum += p
        p *= 1 + growth
    cum += p * (years - n_full)
    return cum


def repay_years(target, profit0, growth, max_years=300):
    """求解回本年限 N：累计利润 = target。"""
    if profit0 <= 0:
        return float("inf")
    if growth <= 0:
        return target / profit0
    cum = 0.0
    p = profit0
    for n in range(1, max_years + 1):
        prev = cum
        cum += p
        if cum >= target:
            return (n - 1) + (target - prev) / p
        p *= 1 + growth
    return float("inf")


def fair_price(hurdle, profit0, growth, shares, compound=True):
    """门槛回报对应的合理股价（元）。"""
    n_limit = math.log(2) / math.log(1 + hurdle) if compound else 1.0 / hurdle
    mcap = cum_profit(profit0, growth, n_limit)
    return mcap / shares, n_limit, mcap


def main():
    ap = argparse.ArgumentParser(description="回本年限法计算器")
    ap.add_argument("--price", type=float, required=True, help="当前股价（元）")
    ap.add_argument("--shares", type=float, required=True, help="总股本（亿股）")
    ap.add_argument("--profit", type=float, required=True, help="当期年利润（亿元）")
    ap.add_argument("--growth", type=float, default=0.0, help="利润年增速（小数）")
    ap.add_argument("--hurdle", type=float, default=0.096,
                    help="门槛回报（小数，默认 0.096 = 9.6%%，本 skill 统一标准）")
    a = ap.parse_args()

    mcap = a.price * a.shares
    n = repay_years(mcap, a.profit, a.growth)
    simple = 1.0 / n
    compound = 2 ** (1.0 / n) - 1

    print("=" * 56)
    print("回本年限法测算")
    print("=" * 56)
    print(f"当前股价        : {a.price:.2f} 元")
    print(f"总股本          : {a.shares:.3f} 亿股")
    print(f"当前市值        : {mcap:.2f} 亿元")
    print(f"年利润（当期）  : {a.profit:.2f} 亿元")
    print(f"利润年增速      : {a.growth * 100:.2f}%")
    print("-" * 56)
    print(f"回本年限        : {n:.2f} 年")
    print(f"年化（简单）    : {simple * 100:.2f}%   (= 100% / N)")
    print(f"年化（复利）    : {compound * 100:.2f}%   (= 2^(1/N) - 1)")
    print("-" * 56)

    fc, n_c, mc_c = fair_price(a.hurdle, a.profit, a.growth, a.shares, compound=True)
    fs, n_s, mc_s = fair_price(a.hurdle, a.profit, a.growth, a.shares, compound=False)
    print(f"门槛回报        : {a.hurdle * 100:.2f}%   （本 skill 统一标准 9.6%）")
    print(f"  复利口径 → 需回本 ≤ {n_c:.2f} 年，合理价 {fc:.2f} 元")
    print(f"  简单口径 → 需回本 ≤ {n_s:.2f} 年，合理价 {fs:.2f} 元")
    print(f"  合理价区间    : {min(fc, fs):.2f} ~ {max(fc, fs):.2f} 元")
    lo = min(fc, fs)
    print(f"  偏低估 (×0.85): {lo * 0.85:.2f} 元")
    print(f"  低估   (×0.70): {lo * 0.70:.2f} 元")
    print("-" * 56)

    if n > 0 and n < float("inf"):
        diff = a.price / fs - 1
        verdict = "高估" if diff > 0.05 else ("低估" if diff < -0.05 else "合理")
        print(f"现价相对合理价（简单口径）: {diff * 100:+.1f}%  → {verdict}")
    print("=" * 56)


if __name__ == "__main__":
    main()
