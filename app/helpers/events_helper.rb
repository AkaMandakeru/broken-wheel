# frozen_string_literal: true

module EventsHelper
  # Format a duration given in minutes as "1h 23m" or "23m".
  def format_duration_minutes(minutes)
    return "—" if minutes.blank? || minutes.to_f.zero?

    total = minutes.to_i
    hours = total / 60
    mins = total % 60
    hours.positive? ? "#{hours}h #{mins}m" : "#{mins}m"
  end

  # Format a pace given in minutes-per-km as "5:30 /km".
  def format_pace(minutes_per_km)
    return "—" if minutes_per_km.blank? || minutes_per_km.to_f.zero?

    whole = minutes_per_km.floor
    seconds = ((minutes_per_km - whole) * 60).round
    if seconds == 60
      whole += 1
      seconds = 0
    end
    format("%d:%02d /km", whole, seconds)
  end

  # Format a distance number, dropping a trailing ".0" => "21" / "10.5".
  def format_km(value)
    return nil if value.blank?

    num = value.to_f
    (num % 1).zero? ? num.to_i.to_s : num.to_s
  end

  # "5 / 10 / 21 km" for an event's offered distances, or its single distance.
  def event_distances_label(event)
    if event.distances.present?
      "#{event.distances.map { |d| format_km(d) }.join(' / ')} km"
    elsif event.distance_km
      "#{format_km(event.distance_km)} km"
    end
  end

  # Build select options for a user's workouts: [label, id].
  def workout_options_for(workouts)
    workouts.map do |w|
      date = w.workout_date&.strftime("%Y-%m-%d")
      sport = t("enums.sports.#{w.sport}", default: w.sport.to_s.capitalize)
      distance = w.distance_km ? "#{w.distance_km} km" : nil
      label = [ date, sport, distance ].compact.join(" · ")
      [ label, w.id ]
    end
  end
end
