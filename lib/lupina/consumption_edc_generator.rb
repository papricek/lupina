# frozen_string_literal: true

require "date"

module Lupina
  class ConsumptionEdcGenerator
    attr_reader :stats

    # consumption_profile: { workday: [24 floats], saturday: [24 floats], sunday: [24 floats] }
    #   Each value 0.0–1.0: relative consumption level at that hour.
    #   No solar envelope — consumption can happen at any hour (bakery at 3am, etc.).
    #   If nil, defaults to flat consumption (1.0 all day).
    def initialize(yearly_consumption_kwh:, month:, year: Date.today.year,
                   consumption_profile: nil, ean: "859182400110224391", seed: nil)
      @yearly_consumption_kwh = yearly_consumption_kwh.to_f
      @month = month
      @year = year
      @consumption_profile = consumption_profile || default_consumption_profile
      @ean = ean
      @rng = seed ? Random.new(seed) : Random.new
      @stats = {}
    end

    def generate
      intervals = build_intervals
      daily_factors = assign_daily_factors

      weights = intervals.map do |i|
        mid = (i[:hour_from] + i[:hour_to]) / 2.0
        profile_val = consumption_profile_at(mid, i[:day_type])
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

    def default_consumption_profile
      flat = Array.new(24, 1.0)
      { workday: flat, saturday: flat, sunday: flat }
    end

    def days_in_month
      Date.new(@year, @month, -1).day
    end

    def days_in_year
      Date.new(@year, 12, 31).yday
    end

    # Consumption is distributed proportionally to days in month (no seasonal solar effect)
    def monthly_consumption_kwh
      @yearly_consumption_kwh * days_in_month / days_in_year.to_f
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

    # --- Consumption profile lookup (interpolated) ---

    def consumption_profile_at(hour, day_type)
      arr = @consumption_profile[day_type] || @consumption_profile[:workday]
      h = hour.floor % 24
      h_next = (h + 1) % 24
      frac = hour - hour.floor
      arr[h] * (1 - frac) + arr[h_next] * frac
    end

    # --- Stats ---

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

    # --- CSV output ---

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
