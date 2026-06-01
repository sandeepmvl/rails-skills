# Bullet config for Rails — drop-in dev + test setup.
#
# 1. Add to Gemfile:
#    group :development, :test do
#      gem "bullet"
#    end
#
# 2. Run: rails g bullet:install  (or paste the after_initialize block manually)
#
# 3. Add the test hooks in spec/rails_helper.rb (see bottom of this file).

# config/environments/development.rb
Rails.application.configure do
  config.after_initialize do
    Bullet.enable        = true
    Bullet.alert         = false  # browser popup off — distracting
    Bullet.bullet_logger = true   # writes log/bullet.log
    Bullet.console       = true   # browser dev-tools console
    Bullet.rails_logger  = true   # tail with `tail -f log/development.log | grep -i bullet`
    Bullet.add_footer    = true   # banner at bottom of every page
    # Bullet.slack       = { webhook_url: ENV["SLACK_BULLET_WEBHOOK"] } if ENV["SLACK_BULLET_WEBHOOK"]

    # Per-association safelist — use sparingly, always with a comment.
    # Bullet.add_safelist type: :n_plus_one_query, class_name: "AdminAuditLog", association: :user
  end
end

# config/environments/test.rb
Rails.application.configure do
  config.after_initialize do
    Bullet.enable = true
    Bullet.raise  = true  # fail specs on any N+1 — that's the whole point
    # Common false positives:
    # Bullet.unused_eager_loading_enable = false  # if your views render conditionally
  end
end

# spec/rails_helper.rb — RSpec hooks
RSpec.configure do |config|
  if Bullet.enable?
    config.before(:each) { Bullet.start_request }
    config.after(:each) do
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
      Bullet.end_request
    end
  end
end

# Minitest equivalent — config/initializers/bullet.rb or test_helper.rb
# class ActiveSupport::TestCase
#   setup    { Bullet.start_request if Bullet.enable? }
#   teardown do
#     if Bullet.enable?
#       Bullet.perform_out_of_channel_notifications if Bullet.notification?
#       Bullet.end_request
#     end
#   end
# end
