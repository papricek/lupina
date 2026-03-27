# frozen_string_literal: true

require "date"

module Lupina
  class EdcGenerator
    attr_reader :stats

    # consumption_pattern:
    #   :afternoon_weekend — high weekday morning load, low afternoon/weekend (commercial/industrial)
    #   :residential       — low daytime, high evening (household)
    #   :flat              — even consumption
    def initialize(capacity_kwp:, yearly_surplus_kwh:, month:, year: Date.today.year,
                   consumption_pattern: :afternoon_weekend, ean: "859182400110224391", seed: nil)
      @capacity_kwp = capacity_kwp.to_f
      @yearly_surplus_kwh = yearly_surplus_kwh.to_f
      @month = month
      @year = year
      @consumption_pattern = consumption_pattern
      @ean = ean
      @rng = seed ? Random.new(seed) : Random.new
      @stats = {}
    end

    def generate
      intervals = build_intervals
      weather_factors = assign_daily_weather

      # Production profile (kW per interval)
      production_raw = intervals.map { |i| production_shape_at(i, weather_factors[i[:date]]) }
      raw_energy = production_raw.sum * 0.25
      prod_scale = raw_energy > 0 ? monthly_production_kwh / raw_energy : 0.0
      production_kw = production_raw.map { |v| v * prod_scale }

      # Consumption profile (shape with noise, then scaled to hit surplus target)
      cons_shape = intervals.map { |i| consumption_shape_at(i) }
      cons_scale = find_consumption_scale(production_kw, cons_shape, monthly_surplus_kwh)
      consumption_kw = cons_shape.map { |v| v * cons_scale }

      compute_stats(intervals, production_kw, consumption_kw)
      build_csv(intervals, production_kw, consumption_kw)
    end

    private

    def days_in_month
      Date.new(@year, @month, -1).day
    end

    def monthly_production_kwh
      @capacity_kwp * SolarModel::SPECIFIC_YIELD * SolarModel::MONTHLY_PRODUCTION_SHARE[@month]
    end

    def monthly_surplus_kwh
      target = @yearly_surplus_kwh * SolarModel::MONTHLY_SURPLUS_SHARE[@month]
      [ target, monthly_production_kwh * 0.95 ].min
    end

    # --- Interval grid ---

    def build_intervals
      (1..days_in_month).flat_map do |day|
        date = Date.new(@year, @month, day)
        weekday = !date.saturday? && !date.sunday?
        96.times.map do |i|
          { date: date, hour_from: i * 0.25, hour_to: (i + 1) * 0.25, weekday: weekday }
        end
      end
    end

    # --- Weather ---

    def assign_daily_weather
      dist = SolarModel::WEATHER_DISTRIBUTION[@month]
      (1..days_in_month).each_with_object({}) do |day, hash|
        date = Date.new(@year, @month, day)
        r = @rng.rand
        idx = if r < dist[0] then 0
        elsif r < dist[0] + dist[1] then 1
        else 2
        end
        lo, hi = SolarModel::WEATHER_FACTOR_RANGES[idx]
        hash[date] = lo + @rng.rand * (hi - lo)
      end
    end

    # --- Production model ---

    def production_shape_at(interval, weather_factor)
      solar = SolarModel::SOLAR_HOURS[@month]
      mid = (interval[:hour_from] + interval[:hour_to]) / 2.0
      return 0.0 if mid <= solar[:rise] || mid >= solar[:set]

      phase = (mid - solar[:rise]) / (solar[:set] - solar[:rise]) * Math::PI
      base = Math.sin(phase)
      noise = 0.85 + @rng.rand * 0.30 # ±15 % intra-day cloud noise
      base * weather_factor * noise
    end

    # --- Consumption model ---

    def consumption_shape_at(interval)
      mid = (interval[:hour_from] + interval[:hour_to]) / 2.0
      base = case @consumption_pattern
      when :afternoon_weekend
        interval[:weekday] ? afternoon_weekend_wd(mid) : afternoon_weekend_we(mid)
      when :minimal
        minimal_consumption(mid)
      when :industrial_lunch_break
        interval[:weekday] ? industrial_lunch_wd(mid) : industrial_lunch_we(mid)
      when :early_shift
        interval[:weekday] ? early_shift_wd(mid) : early_shift_we(mid)
      when :residential
        residential_consumption(mid, interval[:weekday])
      else
        0.5
      end
      base * (0.85 + @rng.rand * 0.30) # ±15 % noise
    end

    # --- Pattern: afternoon_weekend (high morning weekday, drops afternoon) ---

    def afternoon_weekend_wd(h)
      case h
      when 0...6   then 0.15
      when 6...7   then 0.15 + (h - 6) * 0.55
      when 7...8   then 0.70 + (h - 7) * 0.30
      when 8...12  then 1.00
      when 12...13 then 0.65
      when 13...15 then 0.50
      when 15...17 then 0.35
      when 17...19 then 0.25
      when 19...22 then 0.20
      else              0.15
      end
    end

    def afternoon_weekend_we(h)
      case h
      when 0...7   then 0.10
      when 7...20  then 0.15
      else              0.10
      end
    end

    # --- Pattern: minimal (almost no local consumption, near-pure export) ---

    def minimal_consumption(_h)
      0.10 # flat small base load (security, standby)
    end

    # --- Pattern: industrial_lunch_break (weekday full machines, lunch off, weekend nothing) ---

    def industrial_lunch_wd(h)
      case h
      when 0...6   then 0.05
      when 6...7   then 0.50
      when 7...12  then 1.00   # machines full
      when 12...13 then 0.08   # lunch — machines OFF
      when 13...17 then 1.00   # machines full again
      when 17...18 then 0.30
      else              0.05
      end
    end

    def industrial_lunch_we(_h)
      0.03 # weekend — security/standby only
    end

    # --- Pattern: early_shift (production 6-14, then low, weekend nothing) ---

    def early_shift_wd(h)
      case h
      when 0...5   then 0.05
      when 5...6   then 0.30   # prep / arriving
      when 6...14  then 1.00   # production shift
      when 14...15 then 0.20   # winding down
      when 15...22 then 0.08
      else              0.05
      end
    end

    def early_shift_we(_h)
      0.03 # weekend — nothing
    end

    # --- Pattern: residential ---

    def residential_consumption(h, weekday)
      case h
      when 0...6   then 0.15
      when 6...8   then weekday ? 0.50 : 0.20
      when 8...16  then weekday ? 0.20 : 0.30
      when 16...20 then 0.70
      when 20...23 then 0.50
      else              0.20
      end
    end

    # --- Surplus calibration (binary search) ---

    def find_consumption_scale(production_kw, cons_shape, target_surplus_kwh)
      lo = 0.0
      hi = initial_hi(production_kw, cons_shape)

      100.times do
        mid = (lo + hi) / 2.0
        surplus = surplus_for_scale(production_kw, cons_shape, mid)
        return mid if (surplus - target_surplus_kwh).abs < 0.5
        surplus > target_surplus_kwh ? lo = mid : hi = mid
      end
      (lo + hi) / 2.0
    end

    def initial_hi(production_kw, cons_shape)
      min_nonzero = cons_shape.select { |v| v > 0 }.min || 1.0
      (production_kw.max || 100.0) / min_nonzero * 10
    end

    def surplus_for_scale(production_kw, cons_shape, scale)
      production_kw.each_with_index.sum do |p, i|
        net = p - cons_shape[i] * scale
        net > 0 ? net * 0.25 : 0.0
      end
    end

    # --- Stats ---

    def compute_stats(intervals, production_kw, consumption_kw)
      total_surplus = 0.0
      peak_surplus = 0.0

      intervals.each_with_index do |_, idx|
        surplus = [ production_kw[idx] - consumption_kw[idx], 0 ].max
        total_surplus += surplus * 0.25
        peak_surplus = surplus if surplus > peak_surplus
      end

      @stats = {
        month: @month,
        year: @year,
        days: days_in_month,
        capacity_kwp: @capacity_kwp,
        total_surplus_kwh: total_surplus.round(1),
        total_production_kwh: (production_kw.sum * 0.25).round(1),
        peak_surplus_kw: peak_surplus.round(1),
        peak_production_kw: production_kw.max.round(1)
      }
    end

    # --- CSV output ---

    def build_csv(intervals, production_kw, consumption_kw)
      header = "Datum;Cas od;Cas do;IN-#{@ean}-D;OUT-#{@ean}-D"
      rows = intervals.each_with_index.map do |interval, idx|
        surplus_kwh = [ production_kw[idx] - consumption_kw[idx], 0 ].max * 0.25

        date_str = interval[:date].strftime("%d.%m.%Y")
        time_from = format_time(interval[:hour_from])
        time_to   = format_time(interval[:hour_to])
        "#{date_str};#{time_from};#{time_to};#{format_kw(surplus_kwh)};#{format_kw(surplus_kwh)};"
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
