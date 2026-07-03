# Partial Xiaohongshu Benchmark Summary

Date: 2026-07-03

Status: partial. The browsing run was stopped after Xiaohongshu began limiting frequent access. The long run reached roughly 80 accounts in the terminal progress output, but the pre-existing collector wrote only at completion, so only small test corpus files were persisted. The collector has since been fixed to save incrementally after each account.

## Covered Buckets

- Independent developers and self-owned app creators
- AI tool and AI tutorial accounts
- Product manager, product design, and tech media accounts
- One-person-company and startup reflection accounts
- App recommendation and app market intelligence accounts
- Astronomy and science education accounts
- Birding and nature observation accounts
- Puzzle and daily challenge accounts
- Tarot, self-exploration, and emotional reflection accounts

## Strong Signals

- Self-owned product creators are the closest benchmark for this account.
- Tool list accounts have high platform fluency, but they would pull the account away from owned-product promotion.
- AI accounts rely on clear tutorials, saved resources, and strong result framing. Borrow structure, not the exaggerated promise.
- One-person-company accounts create identity and ambition, but income and success-story framing should be avoided.
- Product and design accounts add judgment, taste, and credibility.
- Vertical interest accounts rely on series, community language, and low-friction participation.
- Astronomy and birding samples are sparser, so these products need more education and scene-setting.
- Puzzle samples benefit from daily challenge formats.
- Tarot samples are good at naming emotional questions, but often overpromise outcomes. Soulnio should use reflection and boundaries instead.

## Working Persona Conclusion

The best current direction is:

一个持续做小产品的独立产品创作者。

The account should be about an owned product universe, not about discovering other tools. It should combine creator presence, product scenes, taste, and practical platform structure.

## Writing Rule Conclusion

Each post should start from a concrete scene, introduce one product or one product feature, show what the user can do with it, and end with a bounded action suggestion.

Do not lead with money, downloads, rankings, guaranteed outcomes, or generic AI productivity.

## Next Collection Fix

The collector now saves the corpus incrementally after each account. The next benchmark run can resume with lower speed, fewer accounts per pass, and better preservation.
