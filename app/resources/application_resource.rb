# frozen_string_literal: true

# Base for the mobile API's JSON resources. `params[:viewer]` is the signed-in
# user (or nil), for fields like "is this mine?".
class ApplicationResource
  include Alba::Resource

  private

  def viewer = params[:viewer]
end
