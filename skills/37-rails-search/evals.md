# Evals for `rails-search`

## Prompt 1: "Add search"
**User:** Add a search bar to my blog.
**Expected:** pg_search. Per-model scope with weights. tsvector + trigram. Async indexing.
**Rubric:** [ ] pg_search [ ] Weights [ ] Did not jump to ES

## Prompt 2: "Need typo tolerance"
**User:** Users typing "rais" should find "rails".
**Expected:** trigram threshold in pg_search OR step up to Meilisearch. Trade-off named.
**Rubric:** [ ] Typo strategy [ ] Trade-off

## Prompt 3: "Should I use Elasticsearch?"
**User:** My team wants Elasticsearch. We have 100k posts.
**Expected:** Push back — 100k is small. Postgres handles it. ES is operational overhead.
**Rubric:** [ ] Refused over-engineering [ ] Right tier

## Prompt 4: "Search is slow"
**User:** Searching 5M rows takes 4 seconds.
**Expected:** Precomputed tsvector column + GIN index. Trigger to update.
**Rubric:** [ ] tsvector column [ ] GIN index [ ] Update trigger
