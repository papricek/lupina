# frozen_string_literal: true

module Lupina
  module CzechHolidays
    FIXED_HOLIDAYS = [
      [1, 1], [5, 1], [5, 8], [7, 5], [7, 6],
      [9, 28], [10, 28], [11, 17], [12, 24], [12, 25], [12, 26]
    ].freeze

    def self.holiday?(date)
      FIXED_HOLIDAYS.any? { |m, d| date.month == m && date.day == d } ||
        date == easter_monday(date.year)
    end

    def self.easter_monday(year)
      easter_sunday(year) + 1
    end

    def self.easter_sunday(year)
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = (19 * a + b - d - g + 15) % 30
      i, k = c.divmod(4)
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month, day = (h + l - 7 * m + 114).divmod(31)
      Date.new(year, month, day + 1)
    end

    private_class_method :easter_sunday
  end
end
