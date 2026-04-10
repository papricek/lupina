# frozen_string_literal: true

require "date"

module Lupina
  class EdcGenerator
    include DayResolver

    attr_reader :stats

    def initialize(capacity_kwp:, yearly_surplus_kwh:, month:, year: Date.today.year,
                   surplus_profile: nil, holiday_profile: nil, shutdown_periods: nil,
                   seasonal_overrides: nil, battery_kwh: nil, day_frequency: nil,
                   ean: "859182400110224391", seed: nil)
      @capacity_kwp = capacity_kwp.to_f
      @yearly_surplus_kwh = yearly_surplus_kwh.to_f
      @month = month
      @year = year
      @surplus_profile = surplus_profile || default_surplus_profile
      @holiday_profile = holiday_profile
      @shutdown_periods = shutdown_periods
      @seasonal_overrides = seasonal_overrides
      @battery_kwh = battery_kwh&.to_f
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
        solar_val = solar_envelope(mid)
        noise = 0.85 + @rng.rand * 0.30
        profile_val * solar_val * daily_factors[i[:date]] * noise
      end

      total_weight = weights.sum
      surplus_kwh = if total_weight > 0
        weights.map { |w| (w / total_weight) * monthly_surplus_kwh }
      else
        Array.new(intervals.size, 0.0)
      end

      surplus_kwh = apply_battery_ramp(intervals, surplus_kwh) if @battery_kwh

      compute_stats(intervals, surplus_kwh)
      build_csv(intervals, surplus_kwh)
    end

    private

    def base_profiles
      @surplus_profile
    end

    def default_surplus_profile
      flat = Array.new(24, 1.0)
      WEEKDAY_KEYS.each_with_object({}) { |day, h| h[day] = flat }
    end

    def days_in_month
      Date.new(@year, @month, -1).day
    end

    def monthly_production_kwh
      @capacity_kwp * SolarModel::SPECIFIC_YIELD * SolarModel::MONTHLY_PRODUCTION_SHARE[@month]
    end

    def monthly_surplus_kwh
      @yearly_surplus_kwh * effective_surplus_share
    end

    def effective_surplus_share
      yearly_production = @capacity_kwp * SolarModel::SPECIFIC_YIELD
      ratio = (@yearly_surplus_kwh / yearly_production).clamp(0.0, 1.0)
      prod  = SolarModel::MONTHLY_PRODUCTION_SHARE[@month]
      surp  = SolarModel::MONTHLY_SURPLUS_SHARE[@month]
      surp * (1 - ratio) + prod * ratio
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
        hash[date] = 0.1 + @rng.rand * 1.8
      end
    end

    def solar_envelope(hour)
      solar = SolarModel::SOLAR_HOURS[@month]
      return 0.0 if hour <= solar[:rise] || hour >= solar[:set]

      phase = (hour - solar[:rise]) / (solar[:set] - solar[:rise]) * Math::PI
      Math.sin(phase) ** 3.0
    end

    def apply_battery_ramp(intervals, surplus_kwh)
      result = surplus_kwh.dup
      absorbed_total = 0.0

      dates = intervals.map { |i| i[:date] }.uniq
      dates.each do |date|
        day_indices = intervals.each_index.select { |idx| intervals[idx][:date] == date }
        remaining_capacity = @battery_kwh

        day_indices.each do |idx|
          break if remaining_capacity <= 0
          energy = result[idx]
          next if energy <= 0

          absorbed = [energy, remaining_capacity].min
          result[idx] -= absorbed
          remaining_capacity -= absorbed
          absorbed_total += absorbed
        end
      end

      remaining_total = result.sum
      if remaining_total > 0 && absorbed_total > 0
        scale = (remaining_total + absorbed_total) / remaining_total
        result.map! { |v| v * scale }
      end

      result
    end

    def compute_stats(intervals, surplus_kwh)
      total_surplus = surplus_kwh.sum
      peak_surplus_kw = surplus_kwh.max / 0.25

      @stats = {
        month: @month,
        year: @year,
        days: days_in_month,
        capacity_kwp: @capacity_kwp,
        total_surplus_kwh: total_surplus.round(1),
        total_production_kwh: monthly_production_kwh.round(1),
        peak_surplus_kw: peak_surplus_kw.round(1)
      }
    end

    def build_csv(intervals, surplus_kwh)
      header = "Datum;Cas od;Cas do;IN-#{@ean}-D;OUT-#{@ean}-D"
      rows = intervals.each_with_index.map do |interval, idx|
        date_str = interval[:date].strftime("%d.%m.%Y")
        time_from = format_time(interval[:hour_from])
        time_to   = format_time(interval[:hour_to])
        "#{date_str};#{time_from};#{time_to};#{format_kw(surplus_kwh[idx])};#{format_kw(surplus_kwh[idx])};"
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
