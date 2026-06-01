# Launch Checklist

> Goal: 500 stars in 30 days (floor), 2k+ in 90 days (realistic). Order matters — don't fire everything in one day.

## T-minus 7 days: pre-launch polish

- [ ] All 12 v0.1 skills shipped per the quality checklist in `CLAUDE.md`
- [ ] README has the 30-second before/after demo GIF embedded (record with [asciinema](https://asciinema.org) or Loom, convert to GIF). **This is the highest-leverage single asset.** Spend 4 hours on it.
- [ ] README first paragraph rewritten until it answers in 10 seconds: what is this, who is it for, why does it matter
- [ ] `LICENSE` file (MIT) present
- [ ] `.github/ISSUE_TEMPLATE/` with two templates: "Skill suggestion" and "Skill not working as expected"
- [ ] `.github/FUNDING.yml` if you want sponsorships (optional, but free signal)
- [ ] Pin the repo to your GitHub profile
- [ ] Write a profile README mentioning `rails-skills` as a featured project
- [ ] Star history graph image generated and added to README (use [star-history.com](https://star-history.com))

## T-minus 3 days: warm-up

- [ ] DM 5 Rails developers you know personally (or follow on X). Show them the README. Get blunt feedback. Fix the top 1–2 issues.
- [ ] Post a "coming soon" tease on X with a screenshot of the before/after. Tag @dhh, @obie, @rails. Don't link the repo yet — build curiosity.
- [ ] Write your three launch posts as drafts (HN, r/rails, X thread). Don't post yet.

## Day 1: Tuesday morning Pacific (the main launch)

Order: **HN first**, because HN traffic is fragile and shouldn't compete with itself. Then ripple out.

- [ ] **8:00 AM PT — Show HN.** Title: `Show HN: Rails-Skills – Claude Skills for Ruby on Rails developers`. Body: 3 short paragraphs (problem, what it is, what it isn't). Link the repo. Then for the next 4 hours, reply to every single comment within an hour. **Engagement velocity drives ranking.**
- [ ] **10:00 AM PT — r/rails post.** Title: `I built a pack of AI agent skills for Rails developers`. Same shape as HN post but adapted to Reddit norms (more conversational, less promotional). Cross-post to r/ruby.
- [ ] **11:00 AM PT — X / Twitter thread.** 6–8 tweets. Tweet 1: the hook (one of the "agent breaks my Rails code" stories everyone recognizes). Tweet 2: what `rails-skills` is. Tweets 3–6: the before/after demo, broken into screenshots. Tweet 7: link. Tweet 8: tag @dhh, @obie, @anthropicai, @rubyonrails. Quote-tweet anyone who replies.
- [ ] **Lunchtime — submit to RubyWeekly.** Peter Cooper (@peterc) curates. Email `peter@cooperpress.com` with a short, factual pitch — not a press release. RubyWeekly hits the Tuesday after, but the warm-up matters.
- [ ] **Afternoon — Bluesky post** (Ruby community is migrating there). Same content as X thread but as a single longer post.
- [ ] **End of day — Product Hunt prep.** Don't launch yet; line up a "Hunter" account for next Tuesday. Asset pack: logo, 5 screenshots, 30-sec demo video, tight value prop.

## Day 2–3

- [ ] **Submit to awesome-lists**: open PRs adding rails-skills to `awesome-claude-skills`, `awesome-ruby`, `awesome-rails`, `awesome-claude-code`. These are slow burn but evergreen.
- [ ] **Write a DEV.to article**: "Why AI Coding Agents Fail at Rails — and How I Fixed It". Embed the demo. Link the repo. dev.to is great evergreen SEO for Rails + AI keywords.
- [ ] **Cross-post the DEV article** to your own blog if you have one, Medium, and Hashnode. Canonical URL on whichever you control.
- [ ] **Reply window stays open.** Anyone commenting on HN, Reddit, or X in the first 48 hours gets a real, considered reply. This is what separates 500-star repos from 5k-star ones.

## Day 4–7

- [ ] **Product Hunt launch** (Tuesday or Wednesday). Have your Hunter ready. Mobilize everyone who's already starred to upvote.
- [ ] **Reach out to 2 Ruby podcasts**: Remote Ruby (@chrisoliver, @jasoncharnes), Code with Jason (@jasonswett). Offer to do an episode on "AI coding agents and Rails."
- [ ] **Find 3 Rails YouTubers** with 5k+ subscribers. DM them the repo. Some will make a video.
- [ ] **First content follow-up**: post a "what I learned launching rails-skills" or "the most-requested skill" piece if PR/issue volume warrants it.

## Day 8–30: compounding

- [ ] **Ship one new skill per week.** Each shipped skill is another tweet, another r/rails comment opportunity, another DEV.to short post.
- [ ] **Respond to every issue and PR within 24 hours.** Even a "thanks, I'll look at this tomorrow" reply. Maintainer responsiveness is the second-strongest signal after the README.
- [ ] **Aggregate user testimonials.** Anyone tweeting "this saved me X hours" gets a screenshot saved and added (with permission) to the README "in the wild" section.
- [ ] **Apply to be on the next Anthropic-curated Skills directory.** If Anthropic features it, expect a 5–20x star spike.

## Things that look like marketing but actually drag star growth

- Don't beg for stars in commit messages, README footers, or replies.
- Don't auto-DM people on X.
- Don't post the same launch post to 20 subreddits — that's spam and you'll get banned.
- Don't pay for stars. Nobody will catch it short-term, but the engagement-to-star ratio looks fake and serious developers notice.

## Star projection (be honest with yourself)

| Outcome | Day 30 stars | Day 90 stars | Conditions |
|---|---|---|---|
| Floor (default if you ship + do RubyWeekly + r/rails only) | 300–500 | 700–1,200 | Quality skill, decent README, no viral moment |
| Realistic (full launch checklist executed) | 800–2,000 | 2,500–5,000 | Demo GIF lands, HN front-pages or trends on r/rails, RubyWeekly picks it up |
| Ceiling (one major boost) | 3,000–6,000 | 8,000–15,000 | DHH tweets it, OR Anthropic features it, OR it trends on GitHub for a day |

Stars beyond 15k for a Rails-specific tool are unlikely. Ruby is a smaller pond than Python or JS. Set expectations accordingly — and remember a 5k-star repo in the Ruby ecosystem is *meaningful*. People will know your name.
