# app/controllers/api/v1/base_controller.rb
# Drop-in base controller for Rails 8 API endpoints.
# Pairs with `gem "pagy"`, `gem "jsonapi-serializer"` (or alba), `gem "rack-attack"`.

class Api::V1::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Pundit::Authorization
  include Pagy::Backend

  before_action :authenticate_request!
  after_action :verify_authorized, except: %i[index]
  after_action :verify_policy_scoped, only: %i[index]

  rescue_from ActiveRecord::RecordNotFound,        with: :handle_not_found
  rescue_from ActiveRecord::RecordInvalid,         with: :handle_unprocessable_entity
  rescue_from Pundit::NotAuthorizedError,          with: :handle_forbidden
  rescue_from ActionController::ParameterMissing,  with: :handle_bad_request
  rescue_from ActiveRecord::RecordNotUnique,       with: :handle_conflict

  attr_reader :current_user

  private

  # === Auth ===

  def authenticate_request!
    authenticate_or_request_with_http_token do |token, _options|
      @current_user = User.find_by(api_token: token)
    end
  end

  def request_http_token_authentication(realm = "Application", message = nil)
    render_errors(status: 401, title: "Unauthorized", detail: message || "Authentication required")
  end

  # === Pagination meta ===

  def pagination_meta(pagy)
    {
      current_page: pagy.page,
      per_page: pagy.limit,   # Pagy 9 renamed from .items to .limit
      total_pages: pagy.pages,
      total_count: pagy.count
    }
  end

  # === Error handlers — JSON:API errors shape ===

  def handle_not_found(error)
    render_errors(status: 404, title: "Not Found", detail: error.message)
  end

  def handle_unprocessable_entity(error)
    errors = error.record.errors.map do |e|
      {
        status: "422",
        title: "Validation Failed",
        detail: "#{e.attribute.to_s.humanize} #{e.message}",
        source: { pointer: "/data/attributes/#{e.attribute}" },
        meta: { field: e.attribute, code: e.type }
      }
    end
    render json: { errors: errors }, status: :unprocessable_entity
  end

  def handle_forbidden(_error)
    render_errors(status: 403, title: "Forbidden", detail: "You don't have permission to perform this action")
  end

  def handle_bad_request(error)
    render_errors(status: 400, title: "Bad Request", detail: error.message)
  end

  def handle_conflict(_error)
    render_errors(status: 409, title: "Conflict", detail: "Resource already exists")
  end

  def render_errors(status:, title:, detail: nil, source: nil)
    error = { status: status.to_s, title: title }
    error[:detail] = detail if detail
    error[:source] = source if source
    render json: { errors: [error] }, status: status
  end
end
