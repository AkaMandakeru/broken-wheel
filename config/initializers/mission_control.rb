# frozen_string_literal: true

# /admin/jobs sits behind the admin panel's own sign-in and admin check rather
# than HTTP basic auth.
Rails.application.config.mission_control.jobs.base_controller_class = "Admin::BaseController"
Rails.application.config.mission_control.jobs.http_basic_auth_enabled = false
