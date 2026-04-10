# frozen_string_literal: true

require "date"

module Lupina
  class ConsumptionEdcGenerator
    include DayResolver

    attr_reader :stats

    def initialize(yearly_consumption_kwh:, month:, year: Date.today.year,
                   consumption_profile: nil, holiday_profile: nil, shutdown_periods: nil,
                   seasonal_overrides: nil, monthly_consumption_weights: nil,
                   day_frequency: nil, ean: "859182400110224391", seed: nil)
      @yearly_consumption_kwh = yearly_consumption_kwh.to_f
      @month = month
      @year = year
      @consumption_profile = consumption_profile || default_consumption_profile
      @holiday_profile = holiday_profile
      @shutdown_periods = shutdown_periods
      @seasonal_overrides = seasonal_overrides
      @monthly_consumption_weights = monthly_consumption_weights
      @day_frequency = day_frequency
      @ean = ean
      @rng = seed ? Random.new(seed) : Random.new
      @stats = {}
    end

    def generate
      intervals = build_intervals
      daily_factors = assign_daily_factors

      weights = intervals.map do |i|
        mid = (i[:hour_from] + i[:hour_to]) / 2.0
        profile_val = i[:profile][mid.floor % 24]
        noise = 0.85 + @rng.rand * 0.30
        profile_val * daily_factors[i[:date]] * noise
      end

      total_weight = weights.sum
      consumption_kwh = if total_weight > 0
        weights.map { |w| (w / total_weight) * monthly_consumption_kwh }
      else
        Array.new(intervals.size, 0.0)
      end

      compute_stats(intervals, consumption_kwh)
      build_csv(intervals, consumption_kwh)
    end

    private

    def base_profiles
      @consumption_profile
    end

    def default_consumption_profile
      flat = Array.new(24, 1.0)
      WEEKDAY_KEYS.each_with_object({}) { |day, h| h[day] = flat }
    end

    def days_in_month
      Date.new(@year, @month, -1).day
    end

    def days_in_year
      Date.new(@year, 12, 31).yday
    end

    def monthly_consumption_kwh
      if @monthly_consumption_weights
        @yearly_consumption_kwh * @monthly_consumption_weights[@month - 1]
      else
        @yearly_consumption_kwh * days_in_month / days_in_year.to_f
      end
    end

    def build_intervals
      (1..days_in_month).flat_map do |day|
        date = Date.new(@year, @month, day)
        resolved = resolve_day(date)
        96.times.map do |i|
          { date: date, hour_from: i * 0.25, hour_to: (i + 1) * 0.25,
            day_type: resolved[:day_type], profile: resolved[:profile] }
        end
      end
    end

    def assign_daily_factors
      (1..days_in_month).each_with_object({}) do |day, hash|
        date = Date.new(@year, @month, day)
        hash[date] = 0.7 + @rng.rand * 0.6
      end
    end

    def compute_stats(intervals, consumption_kwh)
      total = consumption_kwh.sum
      peak_kw = consumption_kwh.max / 0.25

      @stats = {
        month: @month,
        year: @year,
        days: days_in_month,
        total_consumption_kwh: total.round(1),
        peak_consumption_kw: peak_kw.round(1)
      }
    end

    def build_csv(intervals, consumption_kwh)
      header = "Datum;Cas od;Cas do;IN-#{@ean}-D;OUT-#{@ean}-D"
      rows = intervals.each_with_index.map do |interval, idx|
        date_str = interval[:date].strftime("%d.%m.%Y")
        time_from = format_time(interval[:hour_from])
        time_to   = format_time(interval[:hour_to])
        "#{date_str};#{time_from};#{time_to};#{format_kw(consumption_kwh[idx])};#{format_kw(consumption_kwh[idx])};"
      end

      ([ header ] + rows).join("\n") + "\n"
    end

    def format_time(hour)
      h = hour.floor % 24
      m = ((hour - hour.floor) * 60).round
      format("%02d:%02d", h, m)
    end

    def format_kw(kw)
      val = (kw * 100).round / 100.0
      str = format("%.2f", val)
      str = str.sub(/0\z/, "") if str.end_with?("0")
      str.tr(".", ",")
    end
  end
end
