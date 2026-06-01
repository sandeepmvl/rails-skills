---
name: activestorage-uploads
description: File uploads in Ruby on Rails 8 with Active Storage — direct uploads to S3/GCS (skip the Rails server for the byte payload), variant configuration with image_processing + libvips, content-type and size validation, pre-signed URL safety (short TTLs, no public buckets by default), analyzer / previewer hooks, processing variants in background jobs (not the request thread), the service config for dev/test/prod. Use when the user mentions Active Storage, file uploads, attach, has_one_attached, has_many_attached, direct uploads, image variants, S3, GCS, image_processing, libvips, signed URLs, or asks how to handle avatars / attachments / photo uploads in Rails.
---

# Active Storage Uploads

> File uploads done right in Rails 8. AI agents generate the simplest possible `has_one_attached :avatar` and call it a day — missing direct uploads (so the Rails server proxies every byte), variant generation (computed in the request thread), and pre-signed URL safety. This skill closes those gaps.

## Why this matters

File uploads are an attack surface and a performance liability. The naïve "user posts the file, Rails saves it" pattern blocks request workers for the duration of the upload, eats RAM on multi-MB files, and gives attackers an easy way to upload malware or oversized payloads. Direct upload + signed URLs + variant generation in jobs fixes all three.

## The opinion

> **Direct uploads to S3/GCS (Rails server never sees the byte payload). image_processing + libvips for variants (NOT imagemagick). Variants generated in background jobs, never in the request. Pre-signed URLs with short TTLs (5–15 min) for downloads. Private buckets by default. Validate content-type + size on the model. Never accept user-provided filenames as URLs.**

Counter-positions:
- **CarrierWave / Shrine** — predate Active Storage. Still legitimate; Shrine especially has features Active Storage lacks (multi-step processing, plugins). Default to Active Storage; reach for Shrine if you need its specific features.
- **Cloudinary / Imgix** — managed image CDNs that handle variants for you. Worth it for image-heavy apps; over-investment for an avatar field.

## Core patterns

### Pattern 1: Direct upload to S3 (skip the Rails server)

**Before** (AI default — every byte through Rails):

```ruby
class User < ApplicationRecord
  has_one_attached :avatar
end
```

```erb
<%= form.file_field :avatar %>
```

User uploads 50MB → Rails server holds the whole thing in memory → forwards to S3. A worker is blocked for the upload duration. Memory spikes. Concurrent uploads OOM.

**After** (direct upload):

```erb
<%= form.file_field :avatar, direct_upload: true %>
```

Plus the JS:

```javascript
// app/javascript/application.js
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()
```

How it works:
1. User selects file. JS calls `POST /rails/active_storage/direct_uploads` with metadata only.
2. Rails returns a pre-signed S3 URL.
3. JS uploads the file directly to S3 with that URL. Rails sees zero bytes.
4. JS submits the form with the blob's signed_id (a small string).
5. Server attaches the already-uploaded blob to the record.

Rails worker time goes from "upload duration" to "milliseconds."

### Pattern 2: Service config (dev / test / prod)

```yaml
# config/storage.yml
test:
  service: Disk
  root: <%= Rails.root.join("tmp/storage") %>

local:
  service: Disk
  root: <%= Rails.root.join("storage") %>

amazon:
  service: S3
  access_key_id: <%= Rails.application.credentials.dig(:aws, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:aws, :secret_access_key) %>
  region: us-east-1
  bucket: myapp-production
  public: false  # CRITICAL — see Pattern 4
  upload:
    server_side_encryption: aws:kms  # SSE-KMS

google:
  service: GCS
  project: myapp
  credentials: <%= Rails.application.credentials.gcp_credentials_json %>
  bucket: myapp-production
  public: false
```

```ruby
# config/environments/production.rb
config.active_storage.service = :amazon
```

```ruby
# config/environments/test.rb
config.active_storage.service = :test
```

**Why per-environment service:** keeps prod uploads in S3 and test uploads in a local tmp dir. No "test ran against prod bucket" disasters.

**`public: false` is critical.** A public bucket means anyone with the URL can download the file forever. We want pre-signed URLs with short TTLs (Pattern 4).

### Pattern 3: Variants with `image_processing` + libvips

```ruby
class User < ApplicationRecord
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb,  resize_to_fill: [80, 80]
    attachable.variant :medium, resize_to_fill: [320, 320]
    attachable.variant :large,  resize_to_limit: [1024, 1024]
  end
end
```

```ruby
# Gemfile
gem "image_processing", "~> 1.13"
# libvips installed at the OS level (faster + lower memory than ImageMagick)
```

```erb
<%= image_tag user.avatar.variant(:thumb) %>
```

**Why libvips over ImageMagick:**
- 5–10× faster.
- ~50% less memory.
- Streams pixels; doesn't load whole image into memory.
- Default in Rails 7+ when you have it installed.

```ruby
# config/application.rb
config.active_storage.variant_processor = :vips
```

**Variants are processed on first access by default.** First request to `/rails/active_storage/representations/...` triggers the processing. On a slow request this can be 500ms+.

### Pattern 4: Pre-signed URLs — short TTLs, never public

**Before** (AI default — exposes the file URL):

```erb
<%= image_tag user.avatar %>
<!-- Renders: <img src="https://myapp.s3.amazonaws.com/...">  -->
<!-- If bucket is public, anyone who saw this URL has it forever. -->
```

**After** (signed URL with short TTL):

```ruby
# config/initializers/active_storage.rb
Rails.application.config.active_storage.urls_expire_in = 5.minutes
```

```erb
<%= image_tag user.avatar %>
<!-- Renders: https://myapp.s3.amazonaws.com/.../?X-Amz-Signature=...&X-Amz-Expires=300 -->
<!-- URL valid for 5 minutes. After that, 403. -->
```

**For longer URLs (e.g. emailed reports):** generate explicitly:

```ruby
url = Rails.application.routes.url_helpers.rails_blob_url(report.pdf, expires_in: 24.hours)
```

**`public: true` in storage.yml** disables signing. Only use for assets that are intentionally public-forever (your CSS files served via Active Storage from CDN, etc.).

### Pattern 5: Validation (content-type, size)

```ruby
class User < ApplicationRecord
  has_one_attached :avatar

  validate :acceptable_avatar

  private

  def acceptable_avatar
    return unless avatar.attached?

    if avatar.byte_size > 5.megabytes
      errors.add(:avatar, "must be under 5MB")
    end

    acceptable_types = %w[image/jpeg image/png image/webp image/gif]
    unless acceptable_types.include?(avatar.content_type)
      errors.add(:avatar, "must be JPEG, PNG, WebP, or GIF")
    end
  end
end
```

**Why validate `content_type`:** users can rename `malware.exe` to `pic.jpg`. Active Storage doesn't sniff; it trusts the upload's MIME header. For strict validation, also check magic bytes:

```ruby
require "marcel"  # ships with Active Storage

def detected_type
  return unless avatar.attached?
  avatar.open do |f|
    Marcel::MimeType.for(f, name: avatar.filename.to_s)
  end
end
```

**Why size matters:** unconstrained file uploads = DoS via disk fill + memory exhaustion during variant processing.

### Pattern 6: Variant generation in background jobs

The default — generate on first access — is fine for small apps. At scale, eager-generate in a job:

```ruby
class GenerateVariantsJob < ApplicationJob
  def perform(blob_id)
    blob = ActiveStorage::Blob.find(blob_id)
    blob.preview(resize_to_limit: [320, 320]).processed if blob.previewable?
    blob.variant(resize_to_limit: [320, 320]).processed if blob.variable?
    blob.variant(resize_to_limit: [1024, 1024]).processed if blob.variable?
  end
end

class User < ApplicationRecord
  has_one_attached :avatar
  after_commit :enqueue_variant_generation, if: :avatar_just_attached?

  private

  def enqueue_variant_generation
    GenerateVariantsJob.perform_later(avatar.blob.id)
  end

  # True only when the avatar was attached during this transaction.
  # Requires Rails 7.1+ — `previously_new_record?` on the attachment is reliable in
  # after_commit from 7.1 onward. On Rails 7.0 and earlier use
  # `avatar.attachment&.id_previously_changed?` instead.
  def avatar_just_attached?
    avatar.attachment&.previously_new_record?
  end
end
```

User uploads. Form submits. Variants generate in background. First view → variants already exist.

### Pattern 7: Removing attachments

```ruby
user.avatar.purge          # synchronous — destroys blob + S3 object
user.avatar.purge_later    # via background job
```

**`purge_later` is the default for `destroy`** — when you delete a user, their attachments enqueue a delete job. Good. Don't override unless you have a reason.

**Watch out for** orphan blobs from interrupted uploads. Cleanup job:

```ruby
class CleanupOrphanBlobsJob < ApplicationJob
  def perform
    # Blobs uploaded but never attached, older than 1 day
    ActiveStorage::Blob
      .where("created_at < ?", 1.day.ago)
      .where.missing(:attachments)
      .find_each(&:purge_later)
  end
end
```

Schedule via Solid Queue `recurring.yml`.

### Pattern 8: CDN in front of Active Storage

For public-ish assets at scale, put CloudFront / Cloudflare / Fastly in front:

```ruby
# config/environments/production.rb
config.action_controller.asset_host = "https://cdn.example.com"
```

For signed URLs through a CDN: the CDN must be configured to forward signed query params and not cache the signature. Cloudflare's "Aggressive" cache modes break this; "Standard" mode is fine.

Or: use the storage service's CDN directly (S3 + CloudFront, GCS + Cloud CDN) for hot-cached blobs.

### Pattern 9: Test fixtures

```ruby
# spec/factories/users.rb
factory :user do
  email { "test@example.com" }

  trait :with_avatar do
    after(:build) do |user|
      user.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
    end
  end
end

# In a spec
let(:user) { create(:user, :with_avatar) }
```

**Test storage service:** keep `service: Disk` rooted at `tmp/storage/`. Wipe `tmp/storage` in `before(:suite)`. Don't use a real S3 service in tests.

## Decision matrix

| Need | Use |
|---|---|
| Avatar / single image per record | `has_one_attached :avatar` + direct upload |
| Gallery / multiple images | `has_many_attached :photos` |
| Image variants | `image_processing` + libvips |
| Cross-environment portability | service config in `storage.yml`, per-env in environments/*.rb |
| Bytes never touch Rails server | `direct_upload: true` on the form field |
| Long-lived download link | `rails_blob_url(blob, expires_in: 24.hours)` |
| Private uploads | `public: false` in storage.yml + signed URLs |
| Many files per record, heavy use | Consider Shrine for advanced processing |
| Image CDN with on-the-fly transforms | Cloudinary / Imgix (paid; Active Storage with libvips + your own CDN is the OSS path) |

## Common mistakes to refuse

- Don't use `public: true` in storage.yml unless intentional (asset CDN).
- Don't generate variants in the request thread on heavy traffic. Use background jobs.
- Don't accept any content-type. Validate.
- Don't accept files of unbounded size. Validate.
- Don't trust the user's `content_type` header — use Marcel to sniff magic bytes for security-critical use.
- Don't use ImageMagick when libvips is available — 5-10× slower.
- Don't store sensitive user content in a public bucket.
- Don't use long-lived (years) signed URLs — default 5 minutes is the right baseline.
- Don't render an image-tag inside an email and expect the signed URL to work weeks later — generate a long-TTL URL explicitly when sending.

## When NOT to use this skill

- The user is asking about static asset serving (CSS, JS) — that's Propshaft, not Active Storage.
- The user needs multi-step file processing (transcoding, OCR pipelines) — consider Shrine.

## See also

- `solid-queue-and-sidekiq` — variant generation jobs
- `rails-security-baseline` — SSRF in URL fetching, signed URL handling
- `n-plus-one-killer` — variant generation N+1 (a gallery view loading 20 thumbnails)
- Coming in v0.2: `external-api-integration` — fetching files from URLs

## Sources

- [Rails Guides — Active Storage Overview](https://guides.rubyonrails.org/active_storage_overview.html)
- [image_processing gem](https://github.com/janko/image_processing)
- [libvips](https://www.libvips.org/) — high-performance image processing
- [Shrine](https://github.com/shrinerb/shrine) (counter-position)
- [Marcel](https://github.com/rails/marcel) — content-type sniffing
- [Active Storage direct upload JS](https://github.com/rails/rails/tree/main/activestorage/app/javascript) — `@rails/activestorage`
- [AWS S3 pre-signed URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html)
- [GCS signed URLs](https://cloud.google.com/storage/docs/access-control/signed-urls)
- [Cloudinary docs](https://cloudinary.com/documentation) — managed alternative
- [OWASP File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html)
