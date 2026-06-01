---
name: rails-search
description: Search in Rails 8 — pg_search as the default (Postgres full-text + tsvector + trigram), Meilisearch when relevance / typo tolerance / autocomplete matter, Elasticsearch / OpenSearch only when you actually need cluster-scale, Searchkick as a friendly wrapper. Multi-search across models. Indexing strategies (sync, async, on-demand). Ranking. Highlighting. Use when the user mentions search, full-text, pg_search, Meilisearch, Elasticsearch, OpenSearch, Searchkick, typo tolerance, autocomplete, indexing, tsvector, trigram, "find users by name", or asks how to add search to a Rails app.
---

# Rails Search

> Three tiers. Use the cheapest one that solves the problem. Most Rails apps never need Elasticsearch — Postgres + pg_search gets you to millions of rows with good UX. AI agents reach for ES by default; this skill pushes back.

## The opinion

> **Default: `pg_search` with PostgreSQL tsvector + pg_trgm. Step up to Meilisearch when you need typo tolerance, autocomplete, and faceted UX. Reach for Elasticsearch / OpenSearch only when you genuinely need clustered, sharded, analytics-grade search at billion-row scale. Use `searchkick` as a Rails-idiomatic wrapper around either Elasticsearch or OpenSearch. Always index in the background, never inline.**

Why this order:
- pg_search uses your existing database. No new infra. No sync drift.
- Meilisearch is a single-binary Rust server. Smaller than ES, sub-50ms queries, typo tolerance built-in.
- ES/OpenSearch is the right tool at scale but operationally expensive — cluster management, JVM tuning, mapping migrations.

## Tier 1: pg_search (default)

### Setup

```ruby
# Gemfile
gem "pg_search"
```

```ruby
# db/migrate/...
class AddPgTrgm < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pg_trgm"  # for fuzzy / similarity
  end
end
```

### Pattern 1: Per-model search

```ruby
class Post < ApplicationRecord
  include PgSearch::Model

  pg_search_scope :search_full_text,
    against: { title: "A", body: "B" },   # weights — A is highest
    using: {
      tsearch: { prefix: true, dictionary: "english" },
      trigram: { threshold: 0.3 }
    }
end

Post.search_full_text("rails search")
# → ranked posts matching either by tsvector or trigram similarity
```

`against: { title: "A", body: "B" }` — Postgres ts_rank weights. `A > B > C > D`. Title matches rank higher than body matches.

### Pattern 2: Multi-search across models

```ruby
class Post < ApplicationRecord
  include PgSearch::Model
  multisearchable against: [:title, :body]
end

class User < ApplicationRecord
  include PgSearch::Model
  multisearchable against: [:name, :bio]
end

PgSearch.multisearch("alice")
# → ActiveRecord::Relation of PgSearch::Document
# Each document has searchable_type ("Post" or "User") and searchable_id.
```

Run `rails generate pg_search:migration:multisearch` then `rails db:migrate` to create the `pg_search_documents` table.

**Important:** `multisearchable` only indexes NEW records via callbacks. Existing rows at the time you add the gem are NOT indexed — multisearch will silently return empty results until you backfill. After adding `multisearchable`, always run:

```ruby
# In a console or rake task — index existing records.
PgSearch::Multisearch.rebuild(Post)
PgSearch::Multisearch.rebuild(User)
```

Re-run after schema changes that affect the indexed columns.

### Pattern 3: tsvector column for big tables

For tables with millions of rows, computing tsvector per query is slow. Precompute:

```ruby
class AddSearchVectorToPosts < ActiveRecord::Migration[8.0]
  def up
    add_column :posts, :search_vector, :tsvector
    add_index :posts, :search_vector, using: :gin
    execute <<~SQL
      UPDATE posts SET search_vector =
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'B');

      CREATE FUNCTION posts_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(NEW.body, '')), 'B');
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER posts_search_vector_update_trigger
      BEFORE INSERT OR UPDATE ON posts
      FOR EACH ROW EXECUTE FUNCTION posts_search_vector_update();
    SQL
  end
end
```

Then in the model:

```ruby
pg_search_scope :search_full_text,
  against: :search_vector,
  using: { tsearch: { tsvector_column: :search_vector, prefix: true } }
```

**Why:** GIN index on tsvector → milliseconds even at 10M rows.

### Pattern 4: Ranking, highlighting, prefix

```ruby
pg_search_scope :search_full_text,
  against: { title: "A", body: "B" },
  using: {
    tsearch: {
      prefix: true,        # "rai" matches "rails"
      highlight: {         # adds highlights to results
        StartSel: "<mark>",
        StopSel: "</mark>"
      }
    }
  }

post = Post.search_full_text("rails").with_pg_search_highlight.first
post.pg_search_highlight  # "<mark>Rails</mark> 8 release notes"
```

## Tier 2: Meilisearch

When pg_search isn't enough — typically when you need:
- Typo tolerance ("rais" finds "rails")
- Instant autocomplete (search-as-you-type)
- Faceted filtering
- Sub-50ms response on multi-million row sets

### Setup

```bash
# Run Meilisearch via Docker
docker run -p 7700:7700 -v $(pwd)/meili_data:/meili_data getmeili/meilisearch:v1.10
```

```ruby
# Gemfile
gem "meilisearch-rails"
```

```ruby
# config/initializers/meilisearch.rb
MeiliSearch::Rails.configuration = {
  meilisearch_url: ENV.fetch("MEILISEARCH_HOST", "http://localhost:7700"),
  meilisearch_api_key: ENV.fetch("MEILISEARCH_API_KEY")
}
```

### Pattern

```ruby
class Post < ApplicationRecord
  include MeiliSearch::Rails

  meilisearch enqueue: ->(record, remove) { MeiliRefreshJob.perform_later(record.class.name, record.id, remove) } do
    attribute :title, :body, :author_name
    searchable_attributes [:title, :body, :author_name]
    filterable_attributes [:status, :published_at]
    sortable_attributes [:published_at]
    ranking_rules ["typo", "words", "proximity", "attribute", "sort", "exactness"]
  end

  def author_name
    author.name
  end
end

Post.search("rails 8")
```

Always set `enqueue:` (with a lambda or `true` for Active Job) — indexing inline blocks the request.

## Tier 3: Searchkick (Elasticsearch / OpenSearch)

When you need:
- Aggregations / analytics across billions of rows
- Multi-cluster, multi-region
- Geo-search at scale
- You already operate an ES cluster

### Setup

```ruby
# Gemfile
gem "searchkick"
gem "elasticsearch", "~> 8.0"  # or "opensearch-ruby" for OpenSearch
```

```ruby
class Post < ApplicationRecord
  searchkick word_start: [:title], suggest: [:title], highlight: [:title, :body]
end

Post.reindex
Post.search("rails", fields: [:title, :body], misspellings: { below: 5 })
```

### Async indexing

```ruby
class Post < ApplicationRecord
  searchkick callbacks: :async  # callbacks via Active Job
end
```

`callbacks: :async` puts indexing in your job queue. Use `:queue` for high-volume bulk indexing through a dedicated queue.

## Indexing strategies

| Strategy | When |
|---|---|
| Inline (sync) | Never. Blocks the request, fails if search is down. |
| Async (after_commit + job) | Default. Reliable, fast UX. |
| Bulk batch (cron / on-demand) | Initial backfill, periodic reconcile against the source of truth. |

```ruby
# app/jobs/index_post_job.rb
class IndexPostJob < ApplicationJob
  queue_as :indexing

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post  # deleted before job ran

    post.update_pg_search_document
  end
end

class Post < ApplicationRecord
  after_commit :enqueue_indexing, on: [:create, :update]
  after_commit :remove_from_index, on: :destroy

  def enqueue_indexing
    IndexPostJob.perform_later(id)
  end

  def remove_from_index
    PgSearch::Document.where(searchable_type: "Post", searchable_id: id).delete_all
  end
end
```

## Reconciliation

External indices drift from the source of truth. Reconcile nightly:

```ruby
class ReconcileSearchIndexJob < ApplicationJob
  queue_as :maintenance

  def perform
    Post.find_each(&:reindex_search)
    # Drop orphans
    PgSearch::Document
      .where(searchable_type: "Post")
      .where.not(searchable_id: Post.select(:id))
      .delete_all
  end
end
```

Run via cron / a recurring Active Job (Rails 8 Solid Queue supports recurring jobs natively).

## Controller pattern

```ruby
class SearchController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    return redirect_to root_path if @query.length < 2

    @pagy, @posts = pagy(Post.search_full_text(@query).with_pg_search_highlight.includes(:author))
  end
end
```

```erb
<!-- app/views/search/index.html.erb -->
<%= form_with url: search_path, method: :get do |f| %>
  <%= f.search_field :q, value: @query, autofocus: true %>
<% end %>

<% @posts.each do |post| %>
  <article>
    <h3><%= link_to post.title, post %></h3>
    <% if post.pg_search_highlight %>
      <p><%= post.pg_search_highlight.html_safe %></p>
    <% end %>
  </article>
<% end %>
```

Sanitize highlight HTML — `html_safe` is acceptable here only because pg_search controls the markup. Never `html_safe` arbitrary user content.

## Common mistakes to refuse

- Don't reach for Elasticsearch by default. Postgres handles 95% of cases.
- Don't index inline (in the request cycle). Always async.
- Don't index huge HTML blobs — extract plain text first (`to_plain_text` for ActionText).
- Don't rebuild the entire index on every deploy.
- Don't index unfiltered user input as the only ranking source — combine with weights.
- Don't trust ES / Meilisearch as source of truth. The DB is. Reconcile periodically.

## When NOT to use this skill

- Lookups by ID, slug, or exact field equality. Use `find_by`. See `activerecord-patterns`.
- Tag filtering with no fuzzy match. Use a join + index, not full-text.
- "Search" that is really "list" — paginate the index page instead.

## See also

- `activerecord-patterns` — non-search queries
- `solid-queue-and-sidekiq` — async indexing jobs
- `actiontext-richtext` — `to_plain_text` for indexing
- `n-plus-one-killer` — `.includes()` results loaded after search

## Sources

- [pg_search gem](https://github.com/Casecommons/pg_search)
- [PostgreSQL full-text search](https://www.postgresql.org/docs/current/textsearch.html)
- [pg_trgm extension](https://www.postgresql.org/docs/current/pgtrgm.html)
- [Meilisearch docs](https://www.meilisearch.com/docs)
- [meilisearch-rails](https://github.com/meilisearch/meilisearch-rails)
- [Searchkick](https://github.com/ankane/searchkick)
- [Elasticsearch Rails](https://github.com/elastic/elasticsearch-rails)
- [OpenSearch Ruby](https://github.com/opensearch-project/opensearch-ruby)
