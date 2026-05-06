# frozen_string_literal: true

require "date"

module Lupina
  # Extrapolates the LLM-produced absolute hourly profiles
  # (workday / weekend / holiday, 24 floats each) into a full month of
  # 15-minute EDC CSV rows.
  #
  # The LLM has already done the hard reasoning (where the curve peaks, what
  # self-consumption pattern applies, what monthly total is plausible). This
  # class only:
  #   1. Picks the right profile per date (workday / weekend / Czech holiday).
  #   2. Splits each hourly_kwh into 4 quarter-hour values.
  #   3. Adds mild multiplicative noise per quarter so the synth CSV doesn't
  #      look glassy.
  #   4. Optionally applies a per-day weather factor (cloudy day = lower).
  #
  # All randomness is seeded for determinism (program.md guarantees seed: 42
  # in the scorer).
  #
  # Tunable knobs (autoresearch will explore these):
  #   - QUARTER_NOISE_RANGE  multiplicative noise per 15-min slot
  #   - DAILY_FACTOR_RANGE   per-day weather variation
  #   - INTRA_HOUR_SHAPE     how a single hour's kWh is distributed across its 4 slots
  class HourlyProfileGenerator
    QUARTER_NOISE_RANGE = (0.90..1.10).freeze
    DAILY_FACTOR_RANGE  = (0.70..1.30).freeze
    # Weights summing to 4.0 — multiply by hourly/4 to get per-slot kWh.
    # [1.0, 1.0, 1.0, 1.0] = uniform within hour. Future tuning may want
    # a slight ramp (e.g. [0.9, 1.0, 1.05, 1.05]) to match real meter behavior.
    INTRA_HOUR_SHAPE = [ 1.0, 1.0, 1.0, 1.0 ].freeze

    def initialize(workday_kwh_per_hour:, weekend_kwh_per_hour:, holiday_kwh_per_hour: nil,
                   month:, year: Date.today.year, ean: "859182400110224391", seed: nil)
      @workday  = workday_kwh_per_hour.dup
      @weekend  = weekend_kwh_per_hour.dup
      @holiday  = holiday_kwh_per_hour&.dup || @weekend
      @month = month.to_i
      @year  = year.to_i
      @ean = ean
      @rng = seed ? Random.new(seed) : Random.new
      @stats = {}
    end

    attr_reader :stats

    def generate
      rows = []
      total_surplus = 0.0
      peak_15min = 0.0

      (1..days_in_month).each do |day|
        date = Date.new(@year, @month, day)
        profile = select_profile(date)
        daily_factor = sample(DAILY_FACTOR_RANGE)

        24.times do |hour|
          hourly_kwh = profile[hour].to_f * daily_factor
          slots = distribute_hour(hourly_kwh)
          slots.each_with_index do |kwh, q|
            kwh = kwh.clamp(0.0, Float::INFINITY)
            total_surplus += kwh
            peak_15min = kwh if kwh > peak_15min

            from_h = hour
            from_m = q * 15
            to_h = (from_m + 15) == 60 ? hour + 1 : hour
            to_m = (from_m + 15) % 60

            rows << format_row(date, from_h, from_m, to_h, to_m, kwh)
          end
        end
      end

      compute_stats(total_surplus, peak_15min)
      build_csv(rows)
    end

    private

    def days_in_month
      Date.new(@year, @month, -1).day
    end

    def select_profile(date)
      return @holiday if CzechHolidays.holiday?(date)
      return @weekend if date.wday == 0 || date.wday == 6
      @workday
    end

    def distribute_hour(hourly_kwh)
      base = hourly_kwh / 4.0
      INTRA_HOUR_SHAPE.map { |w| base * w * sample(QUARTER_NOISE_RANGE) }
    end

    def sample(range)
      range.min + @rng.rand * (range.max - range.min)
    end

    def format_row(date, from_h, from_m, to_h, to_m, kwh)
      date_str = date.strftime("%d.%m.%Y")
      from_str = format("%02d:%02d", from_h % 24, from_m)
      to_str   = format("%02d:%02d", to_h % 24, to_m)
      val = format_kw(kwh)
      "#{date_str};#{from_str};#{to_str};#{val};#{val};"
    end

    def format_kw(kw)
      val = (kw * 100).round / 100.0
      str = format("%.2f", val)
      str = str.sub(/0\z/, "") if str.end_with?("0")
      str.tr(".", ",")
    end

    def compute_stats(total_surplus, peak_15min)
      @stats = {
        month: @month,
        year: @year,
        days: days_in_month,
        total_surplus_kwh: total_surplus.round(1),
        peak_surplus_kw: (peak_15min * 4).round(1)
      }
    end

    def build_csv(rows)
      header = "Datum;Cas od;Cas do;IN-#{@ean}-D;OUT-#{@ean}-D"
      ([ header ] + rows).join("\n") + "\n"
    end
  end
end
