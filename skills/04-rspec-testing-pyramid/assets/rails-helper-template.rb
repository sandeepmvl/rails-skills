# spec/rails_helper.rb — drop-in template.

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "capybara/rails"
require "capybara/rspec"
require "webmock/rspec"

# WebMock — disallow real HTTP by default, allow localhost for system specs
WebMock.disable_net_connect!(allow_localhost: true)

# Cuprite — fast headless Chrome via CDP
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1400, 900],
    headless: ENV.fetch("HEADLESS", "true") == "true",
    js_errors: true,
    timeout: 10,
    process_timeout: 10
  )
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5

# VCR — record cassettes for external HTTP
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/cassettes")
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = { record: :once, match_requests_on: %i[method uri] }
  config.ignore_localhost = true

  # Filter every credential — never commit them to cassettes
  config.filter_sensitive_data("<STRIPE_SECRET_KEY>") { ENV["STRIPE_SECRET_KEY"] }
  config.filter_sensitive_data("<HUBSPOT_API_KEY>")   { ENV["HUBSPOT_API_KEY"] }
  config.filter_sensitive_data("<AUTH_HEADER>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end
end

# Load every file in spec/support automatically
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

# Run pending migrations before any spec
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = ["#{Rails.root}/spec/fixtures"]
  config.use_transactional_fixtures = true

  # For JS system specs that need real commits across threads, switch DatabaseCleaner
  # to truncation. Do NOT try to flip `use_transactional_tests` in before(:each) — the
  # transaction is already open by then.
  config.before(:each, type: :system) { driven_by(:rack_test) }
  config.before(:each, type: :system, js: true) { driven_by(:cuprite) }
  if defined?(DatabaseCleaner)
    config.before(:suite) { DatabaseCleaner.strategy = :transaction }
    config.before(:each)  { DatabaseCleaner.strategy = :transaction; DatabaseCleaner.start }
    config.before(:each, type: :system, js: true) { DatabaseCleaner.strategy = :truncation }
    config.after(:each)  { DatabaseCleaner.clean }
  end

  # Infer spec type from file location (request, system, model, etc.)
  config.infer_spec_type_from_file_location!

  # Trim backtraces of framework noise
  config.filter_rails_from_backtrace!

  # FactoryBot — short syntax: create / build / build_stubbed / attributes_for
  config.include FactoryBot::Syntax::Methods

  # Devise / authentication helpers (if using Devise)
  # config.include Devise::Test::IntegrationHelpers, type: :request
  # config.include Devise::Test::ControllerHelpers, type: :controller
  # config.include Warden::Test::Helpers, type: :system
  # config.after(:each, type: :system) { Warden.test_reset! }

  # Time travel helpers
  config.include ActiveSupport::Testing::TimeHelpers

  # Reset Bullet on every example (see n-plus-one-killer)
  if defined?(Bullet) && Bullet.enable?
    config.before(:each) { Bullet.start_request }
    config.after(:each) do
      Bullet.perform_out_of_channel_notifications if Bullet.notification?
      Bullet.end_request
    end
  end

  # Reset Prosopite scan per example (if using)
  if defined?(Prosopite)
    config.before(:each) { Prosopite.scan }
    config.after(:each)  { Prosopite.finish }
  end
end

# Shoulda Matchers (if using)
# Shoulda::Matchers.configure do |config|
#   config.integrate do |with|
#     with.test_framework :rspec
#     with.library :rails
#   end
# end
