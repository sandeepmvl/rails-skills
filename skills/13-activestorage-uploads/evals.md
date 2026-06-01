# Evals for `activestorage-uploads`

## Prompt 1: "Upload avatar"

**User prompt:**
> User model needs an avatar upload. What's the right setup?

**Expected:**
- `has_one_attached :avatar`.
- `direct_upload: true` on the file_field.
- Validation: max 5MB, content-type whitelist.
- service: Disk in dev, S3 in prod.

**Rubric:**
- [ ] has_one_attached
- [ ] direct_upload mentioned
- [ ] Validation added
- [ ] Service config per-env

---

## Prompt 2: "Why are uploads slow?"

**User prompt:**
> When users upload a 20MB photo, my Rails server hangs for the duration. Other requests slow down.

**Expected:**
- Identifies: Rails is proxying the bytes (direct_upload off).
- Fix: enable `direct_upload: true`. Skip Rails entirely.
- Mentions JS bundling for `@rails/activestorage`.

**Rubric:**
- [ ] Diagnosed proxying-through-Rails issue
- [ ] direct_upload as fix
- [ ] JS setup mentioned

---

## Prompt 3: "Pre-signed URL leak"

**User prompt:**
> Should I use `public: true` so users can share their photo URLs?

**Expected:**
- Refuses for user content.
- Recommends private bucket + signed URLs.
- Mentions `urls_expire_in: 5.minutes` default.
- For sharing: generate longer-TTL URLs explicitly.

**Rubric:**
- [ ] Refused public bucket for user content
- [ ] Signed URLs with TTL
- [ ] Long-TTL pattern for sharing

---

## Prompt 4: "Variants are slow"

**User prompt:**
> My gallery page loads slow. Each thumbnail variant is computed on first access.

**Expected:**
- Eager-generate variants in a background job.
- Job triggered on after_commit / on attachment.
- libvips over ImageMagick.

**Rubric:**
- [ ] Background job for variants
- [ ] libvips recommended
- [ ] After_commit trigger

---

## Prompt 5: "Should I use Shrine instead?"

**User prompt:**
> Should I use Shrine instead of Active Storage?

**Expected:**
- Default Active Storage for new apps.
- Shrine when: multi-step processing, plugins, advanced features.
- Not a "Shrine is better" reflex.

**Rubric:**
- [ ] Active Storage as default
- [ ] Shrine trigger conditions
- [ ] Neither dismissed

---

## Prompt 6: "Validate uploaded file is actually an image"

**User prompt:**
> User can upload anything with a .jpg extension. How do I check it's actually an image?

**Expected:**
- Validate `content_type` (header).
- For security-critical use, sniff magic bytes with Marcel.
- Mentions `Marcel::MimeType.for(file)`.

**Rubric:**
- [ ] content_type validation
- [ ] Marcel for magic-byte sniffing
- [ ] Did not just trust the extension
