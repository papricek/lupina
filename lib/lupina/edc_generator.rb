# frozen_string_literal: true

require "date"

module Lupina
  class EdcGenerator
    attr_reader :stats

    # surplus_profile: { workday: [24 floats], saturday: [24 floats], sunday: [24 floats] }
    #   Each value 0.0–1.0: fraction of solar production that becomes surplus at that hour.
    #   The generator applies a solar envelope per month to shape the output realistically.
    #   If nil, defaults to full surplus (1.0 all day) — all production goes to grid.
    def initialize(capacity_kwp:, yearly_surplus_kwh:, month:, year: Date.today.year,
                   surplus_profile: nil, ean: "859182400110224391", seed: nil)
      @capacity_kwp = capacity_kwp.to_f
      @yearly_surplus_kwh = yearly_surplus_kwh.to_f
      @month = month
      @year = year
      @surplus_profile = surplus_profile || default_surplus_profile
      @ean = ean
      @rng = seed ? Random.new(seed) : Random.new
      @stats = {}
    end

    def generate
      intervals = build_intervals
      daily_factors = assign_daily_factors

      # Compute surplus weight for each 15-min interval
      weights = intervals.map do |i|
        mid = (i[:hour_from] + i[:hour_to]) / 2.0
        profile_val = surplus_profile_at(mid, i[:day_type])
        solar_val = solar_envelope(mid)
        noise = 0.85 + @rng.rand * 0.30
        profile_val * solar_val * daily_factors[i[:date]] * noise
      end

      # Distribute monthly surplus proportionally to weights
      total_weight = weights.sum
      surplus_kwh = if total_weight > 0
        weights.map { |w| (w / total_weight) * monthly_surplus_kwh }
      else
        Array.new(intervals.size, 0.0)
      end

      compute_stats(intervals, surplus_kwh)
      build_csv(intervals, surplus_kwh)
    end

    private

    def default_surplus_profile
      flat = Array.new(24, 1.0)
      { workday: flat, saturday: flat, sunday: flat }
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

    # When surplus is a large fraction of production, the monthly surplus
    # distribution must follow the production curve. Blend surplus shares
    # toward production shares proportionally to the surplus/production ratio.
    def effective_surplus_share
      yearly_production = @capacity_kwp * SolarModel::SPECIFIC_YIELD
      ratio = (@yearly_surplus_kwh / yearly_production).clamp(0.0, 1.0)
      prod  = SolarModel::MONTHLY_PRODUCTION_SHARE[@month]
      surp  = SolarModel::MONTHLY_SURPLUS_SHARE[@month]
      surp * (1 - ratio) + prod * ratio
    end

    # --- Interval grid ---

    def build_intervals
      (1..days_in_month).flat_map do |day|
        date = Date.new(@year, @month, day)
        day_type = if date.sunday?
          :sunday
        elsif date.saturday?
          :saturday
        else
          :workday
        end
        96.times.map do |i|
          { date: date, hour_from: i * 0.25, hour_to: (i + 1) * 0.25, day_type: day_type }
        end
      end
    end

    # --- Daily variation (±30%) ---

    def assign_daily_factors
      (1..days_in_month).each_with_object({}) do |day, hash|
        date = Date.new(@year, @month, day)
        hash[date] = 0.7 + @rng.rand * 0.6
      end
    end

    # --- Surplus profile lookup (interpolated) ---

    def surplus_profile_at(hour, day_type)
      arr = @surplus_profile[day_type] || @surplus_profile[:workday]
      h = hour.floor % 24
      h_next = (h + 1) % 24
      frac = hour - hour.floor
      arr[h] * (1 - frac) + arr[h_next] * frac
    end

    # --- Solar envelope (sin curve between sunrise and sunset) ---

    def solar_envelope(hour)
      solar = SolarModel::SOLAR_HOURS[@month]
      return 0.0 if hour <= solar[:rise] || hour >= solar[:set]

      phase = (hour - solar[:rise]) / (solar[:set] - solar[:rise]) * Math::PI
      Math.sin(phase)
    end

    # --- Stats ---

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

    # --- CSV output ---

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
