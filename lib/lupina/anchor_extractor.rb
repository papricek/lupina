# frozen_string_literal: true

module Lupina
  # Extracts numeric anchors from a Czech solar/EDC description: monthly totals,
  # daily totals, peak window, active window. The output is prepended to the
  # HourlyProfileParser LLM prompt with calibration framing so the LLM works
  # against explicit numeric targets without losing its own seasonal reasoning.
  #
  # Conservative by design: better to miss than to mislead.
  module AnchorExtractor
    MONTH_PATTERNS = [
      [ /\b(?:v\s+)?led(?:en|na|nu|ně)\b/i,                 1, "leden" ],
      [ /\b(?:v\s+)?(?:únor[uěya]?|únoru)\b/i,              2, "únor" ],
      [ /\b(?:v\s+)?(?:březen|března|březnu)\b/i,           3, "březen" ],
      [ /\b(?:v\s+)?(?:duben|dubna|dubnu)\b/i,              4, "duben" ],
      [ /\b(?:v\s+)?(?:květen|května|květnu)\b/i,           5, "květen" ],
      [ /\b(?:v\s+)?(?:červen|června|červnu)(?!c)\b/i,      6, "červen" ],
      [ /\b(?:v\s+)?(?:červenec|července|červenci)\b/i,     7, "červenec" ],
      [ /\b(?:v\s+)?(?:srpen|srpna|srpnu)\b/i,              8, "srpen" ],
      [ /\b(?:v\s+)?září\b/i,                               9, "září" ],
      [ /\b(?:v\s+)?(?:říjen|října|říjnu)\b/i,              10, "říjen" ],
      [ /\b(?:v\s+)?(?:listopad|listopadu)\b/i,             11, "listopad" ],
      [ /\b(?:v\s+)?(?:prosinec|prosince|prosinci)\b/i,     12, "prosinec" ]
    ].freeze

    AMOUNT_RE = /(\d{1,3}(?:[\s.,]\d{1,3})*)\s*(MWh|kWh|MW|kW)\b/i
    RANGE_RE  = /(\d{1,2})\s*[-–]\s*(\d{1,2})/

    class << self
      def call(text)
        text = text.to_s
        {
          monthly_totals:  extract_monthly_totals(text),
          daily_totals:    extract_daily_totals(text),
          peak_window:     extract_window(text, /špič(?:k[auěy]|ka)|vrchol/i, 50),
          active_window:   extract_window(text, /aktivně|profil\s+(?:úzký|široký|rozkročený)|(?:šíř|širok)/i, 60)
        }
      end

      def format_for_prompt(anchors, target_month:)
        lines = []

        target = anchors[:monthly_totals].find { |a| a[:month] == target_month }
        if target
          lines << "- ★ #{czech_month(target_month).upcase} měsíční úhrn: ~#{target[:kwh]} kWh (z popisu)"
        end

        other_months = anchors[:monthly_totals].reject { |a| a[:month] == target_month }
        other_months.each do |a|
          lines << "- #{czech_month(a[:month])} ~#{a[:kwh]} kWh (sezónní reference, ne cílový měsíc)"
        end

        anchors[:daily_totals].each do |a|
          label = case a[:kind]
                  when "weekday" then "všední den"
                  when "weekend" then "víkend"
                  else "denně (průměr)"
                  end
          lines << "- Denní úhrn (#{label}): ~#{a[:kwh]} kWh"
        end

        if (w = anchors[:peak_window])
          lines << "- Špička aktivity (z popisu): #{w[:start]}–#{w[:end]} h"
        end
        if (w = anchors[:active_window])
          lines << "- Aktivní okno (z popisu): #{w[:start]}–#{w[:end]} h"
        end

        return "" if lines.empty?

        header = "KALIBRAČNÍ SIGNÁLY Z POPISU (pomocné anchory — použij je k upřesnění tvého odhadu, " \
                 "ale stále aplikuj sezónnost a vlastní rozumnost):"
        "#{header}\n#{lines.join("\n")}\n\n"
      end

      private

      def extract_monthly_totals(text)
        amounts = []
        text.scan(AMOUNT_RE) do |num_str, unit|
          m = Regexp.last_match
          amounts << { pos: m.begin(0), num: num_str, unit: unit, raw: m[0] }
        end

        results = []
        MONTH_PATTERNS.each do |re, month_num, _|
          text.scan(re) do
            m = Regexp.last_match
            mpos = m.begin(0)
            nearest = amounts.map { |a| [ a, a[:pos] - mpos ] }
                             .select { |_, d| (d >= 0 && d < 35) || (d < 0 && d > -6) }
                             .reject { |a, _|
                               MONTH_PATTERNS.any? do |re2, mn2, _|
                                 next false if mn2 == month_num
                                 mm = text.match(re2, [ mpos + m[0].length, 0 ].max)
                                 mm && mm.begin(0) < a[:pos] && (a[:pos] - mm.begin(0)) < (a[:pos] - mpos).abs
                               end
                             }
                             .min_by { |_, d| d.abs }
            next unless nearest
            amount = nearest.first
            kwh = parse_amount(amount[:num], amount[:unit])
            next unless kwh
            next if results.any? { |r| r[:month] == month_num && (r[:kwh] - kwh).abs < kwh * 0.01 }
            results << { month: month_num, kwh: kwh.round, raw: "#{m[0]} ~ #{amount[:raw]}" }
          end
        end
        results
      end

      def extract_daily_totals(text)
        results = []
        already_paired = []

        text.scan(/(\d+(?:[,.]\d+)?)\s*(?:vs\.?|versus|proti)\s*(\d+(?:[,.]\d+)?)\s*kWh\s*\/?\s*den/i) do |a_str, b_str|
          pre = (Regexp.last_match.pre_match[-150..] || Regexp.last_match.pre_match).downcase
          a = a_str.tr(",", ".").to_f
          b = b_str.tr(",", ".").to_f
          larger, smaller = [ a, b ].max, [ a, b ].min
          weekend_higher = pre =~ /víkend\w*[^.]{0,60}(?:víc|nad|vyšší|více|dvakrát)/i ||
                           pre =~ /(?:víc|nad|vyšší|více)\s+\S{0,30}(?:o\s+)?\S*\s*víkend/i
          weekend_lower  = pre =~ /víkend\w*[^.]{0,60}(?:pod|méně|nižší)/i

          if weekend_higher
            results << { kind: "weekend", kwh: larger.round }
            results << { kind: "weekday", kwh: smaller.round }
          elsif weekend_lower
            results << { kind: "weekday", kwh: larger.round }
            results << { kind: "weekend", kwh: smaller.round }
          elsif pre =~ /víkend|všedn/i
            results << { kind: "weekend", kwh: larger.round }
            results << { kind: "weekday", kwh: smaller.round }
          else
            results << { kind: "average", kwh: a.round }
            results << { kind: "average", kwh: b.round }
          end
          already_paired << a.round << b.round
        end

        text.scan(/(\d+(?:[,.]\d+)?)\s*kWh\s*\/?\s*den/i) do |amt_str,|
          val = amt_str.tr(",", ".").to_f.round
          next if val.zero?
          next if already_paired.include?(val)
          before = (Regexp.last_match.pre_match[-40..] || Regexp.last_match.pre_match).downcase
          kind = case before
                 when /víkend/ then "weekend"
                 when /všedn|prac/ then "weekday"
                 else "average"
                 end
          next if results.any? { |r| r[:kwh] == val && r[:kind] == kind }
          results << { kind: kind, kwh: val }
        end

        results
      end

      def extract_window(text, keyword_re, search_distance)
        pos = 0
        while (m = text.match(keyword_re, pos))
          local_end = [ m.end(0) + search_distance, text.length ].min
          local = text[m.begin(0)...local_end]
          if (rm = local.match(RANGE_RE))
            s, e = rm[1].to_i, rm[2].to_i
            return { start: s, end: e, raw: m[0] } if s.between?(0, 23) && e.between?(0, 23) && e > s && (e - s) <= 16
          end
          pos = m.end(0)
        end
        nil
      end

      def parse_amount(num_str, unit)
        cleaned = num_str.gsub(/\s/, "").tr(",", ".")
        if cleaned.count(".") > 1
          parts = cleaned.split(".")
          decimals = parts.pop
          cleaned = parts.join + "." + decimals
        end
        val = cleaned.to_f
        return nil if val.zero?
        unit.downcase.start_with?("m") ? val * 1000 : val
      end

      def czech_month(num)
        %w[leden únor březen duben květen červen červenec srpen září říjen listopad prosinec][num - 1]
      end
    end
  end
end
