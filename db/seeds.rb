# frozen_string_literal: true

# Create sample challenges
Challenge.find_or_create_by!(title: "Weekly Run 20km") do |c|
  c.description = "Run 20km this week"
  c.challenge_type = "weekly"
  c.sport = "run"
  c.target_value = 20
  c.target_unit = "km"
  c.starts_at = Date.current.beginning_of_week
  c.ends_at = Date.current.end_of_week
  c.status = "active"
end

Challenge.find_or_create_by!(title: "Monthly Bike 200km") do |c|
  c.description = "Bike 200km this month"
  c.challenge_type = "monthly"
  c.sport = "bike"
  c.target_value = 200
  c.target_unit = "km"
  c.starts_at = Date.current.beginning_of_month
  c.ends_at = Date.current.end_of_month
  c.status = "active"
end
