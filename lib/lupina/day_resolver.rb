# frozen_string_literal: true

module Lupina
  module DayResolver
    WEEKDAY_KEYS = %i[sunday monday tuesday wednesday thursday friday saturday].freeze
    ZEROS = Array.new(24, 0.0).freeze

    def resolve_day(date)
      profiles = active_profile_set(date.month)
      holiday = active_holiday_profile(date.month)

      if in_shutdown?(date)
        return { day_type: :holiday, profile: holiday || ZEROS }
      end

      if holiday && CzechHolidays.holiday?(date)
        return { day_type: :holiday, profile: holiday }
      end

      weekday = WEEKDAY_KEYS[date.wday]

      if @day_frequency && @day_frequency[weekday]
        day_rng = Random.new(@rng.seed ^ date.jd)
        unless day_rng.rand < @day_frequency[weekday]
          return { day_type: :holiday, profile: holiday || ZEROS }
        end
      end

      profile = profiles[weekday] || profiles[:monday] || ZEROS
      { day_type: weekday, profile: profile }
    end

    private

    def active_profile_set(month)
      return base_profiles unless @seasonal_overrides
      override = @seasonal_overrides.find { |o| o[:months].include?(month) }
      override ? override[:profiles] : base_profiles
    end

    def active_holiday_profile(month)
      if @seasonal_overrides
        override = @seasonal_overrides.find { |o| o[:months].include?(month) }
        return override[:holiday_profile] if override&.key?(:holiday_profile)
      end
      @holiday_profile
    end

    def in_shutdown?(date)
      return false unless @shutdown_periods
      md = format("%02d-%02d", date.month, date.day)
      @shutdown_periods.any? do |period|
        if period[:from] <= period[:to]
          md >= period[:from] && md <= period[:to]
        else
          md >= period[:from] || md <= period[:to]
        end
      end
    end
  end
end
