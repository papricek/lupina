# frozen_string_literal: true

module Lupina
  module SolarModel
    # Typical specific yield for Czech Republic (~50°N)
    SPECIFIC_YIELD = 1000 # kWh/kWp/year

    # Monthly share of yearly production (sums to 1.0)
    MONTHLY_PRODUCTION_SHARE = {
      1 => 0.025, 2 => 0.040, 3 => 0.080, 4 => 0.110, 5 => 0.130, 6 => 0.140,
      7 => 0.135, 8 => 0.120, 9 => 0.090, 10 => 0.065, 11 => 0.035, 12 => 0.030
    }.freeze

    # Monthly share of yearly surplus (more concentrated in summer, sums to 1.0)
    MONTHLY_SURPLUS_SHARE = {
      1 => 0.010, 2 => 0.020, 3 => 0.055, 4 => 0.090, 5 => 0.140, 6 => 0.170,
      7 => 0.165, 8 => 0.140, 9 => 0.095, 10 => 0.055, 11 => 0.035, 12 => 0.025
    }.freeze

    # Approximate sunrise/sunset hours for 50°N (Prague), with DST (Apr-Oct)
    SOLAR_HOURS = {
      1  => { rise: 7.75, set: 16.25 },
      2  => { rise: 7.00, set: 17.25 },
      3  => { rise: 6.00, set: 18.25 },
      4  => { rise: 6.25, set: 20.00 },
      5  => { rise: 5.25, set: 20.75 },
      6  => { rise: 4.75, set: 21.25 },
      7  => { rise: 5.00, set: 21.00 },
      8  => { rise: 5.75, set: 20.25 },
      9  => { rise: 6.50, set: 19.25 },
      10 => { rise: 6.25, set: 17.50 },
      11 => { rise: 7.00, set: 16.25 },
      12 => { rise: 7.50, set: 16.00 }
    }.freeze

  end
end
