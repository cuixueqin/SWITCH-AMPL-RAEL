# updated to include hydro 11/7/07
# major update  11/28/07
#   to specify study periods exogenously and allow samples that cover fractional
#   numbers of hours
# updated 12/13/07 
#   to assume whole days are sampled, and apply each month's hydro limits to each full
#   day. this is necessary to incorporate any sort of stored-resource dispatch, because
#   if the dispatch model works with randomly sampled hours, each day will have a
#   flatter set of hourly conditions than is realistic (i.e., the day will include
#   some high-wind and some low-wind hours, so that the total storage needed for the
#   day is close to zero. In reality, there will be some days that are windy all day
#   and some that have low-wind all day.) Unfortunately, until the model can be greatly
#   expanded, it won't be able to do multi-day storage and dispatch decisions. The
#   previous system used seasonal dispatch rules for hydro, but that could allow
#   "storage" of power during a sample that comes from a low-hydro year and then using
#   more stored power during a sample that comes from a high-hydro year. This system 
#   uses (used) hourly dispatch for all hydro facilities, but that was slow.
# updated 12/24/07
#   to dispatch simple hydro using season-hour rules (as before 12/13/07)
#   and to include pumped hydro, with each facility dispatched hourly 
#   (as was done with simple hydro in the 12/13/07 version)
#   season-hour rules are quicker to optimize (2200 s instead of 4400 s) 
#   and allow more renewables (66.2% instead of 65.2%), 
#   but are hard to use for pumped hydro because of the round-trip efficiency losses
#   (solution time is about 900 s with season-hour rules and no pumped hydro)
# added transmission line losses 12/28/07, to be more realistic and to make the model
#   prefer to dispatch local gas plants instead of ones in other zones 
#   (adds about 10% to solution time)
# 1/16/08: added existing power plants and transmission lines 
#   (solution time for $85, with individual hydro dispatch: 8400 s; 150-300 s to move to $80 solution)
# 2/7/08: added variables and constraints to ensure 15% extra capacity every hour 
#   (solution time for $85 with indiv. hydro: 19191 s; then 440s to move from $85 solution to $80)
#   LP Presolve eliminated 455594 rows and 161015 columns.
#   Reduced LP has 261551 rows, 508642 columns, and 6973630 nonzeros.
#   Barrier method:
# ***NOTE: Found 76 dense columns.
# Number of nonzeros in lower triangle of A*A' = 163698997
# Using Nested Dissection ordering
# Total time for automatic ordering = 3204.36 sec.
# Summary statistics for Cholesky factor:
#   Rows in Factor            = 261627
#   Integer space required    = 2399027
#   Total non-zeros in factor = 744509101
#   Total FP ops to factor    = 4348384748541
# (16 hours to solve)
# 2/8/08: switched reserve calculation to use total capacity of new and existing dispatchable 
#   (non-hydro) plants, and not to calculate hourly dispatch for them. (no effect on problem size or solution time)
# 3/14/08: 
#   changed ep_fixed_cost calculation to discount annual costs within each period to the start of the period
#   changed objective function to (correctly) multiply ep_capital_cost and ep_fixed_cost by the size of each plant
#   switched to 4x4-year periods, beginning in 2010, instead of 4x3-year periods beginning in 2015
#   added peak load days (with 1-day's weight) during each month
#   (solution time is now 94000 s with indiv. hydro, hourly dispatch of reserves, $80 carbon tax; 3300 s to move from $80 to $90)
# 4/28/08: lots of little changes
#  converted transmission dispatch constraints to be bidirectional, and use the known wecc path limits where applicable
#  switched transmission constraint from forward + backward <= limit to forward <= limit, backward <= limit
#  added a (crude) calculation for the "cost" of existing hydro plants
#  changed date indexing in source data so each simulated date is uniquely indexed, 
#   even if the same historical date is used in multiple investment periods
#   (still can't refer to the same historical date twice in the same investment period, but there's no reason to do that anyway)
#  added small hydro (<50MW) plants to the source data, with min=avg=max requirement (i.e., in baseload mode)
#  changed wind data to convert estimated production for 2020 turbines into 2010 values,
#    and improved the creation of augmented, low-speed wind sites
#  removed redundant vintage range specification from EP_BASELOAD_PERIODS definition
#    because it was already specified in EP_PERIODS
# 06/29/09 Josiah and Jimmy Regionalized plant costs
# 07/03/09 Jimmy (attempted) to make costs all in $/MW instead of the previous mix of $/MW and $/kW.
# 	 and also added Biomass

###############################################
#
# Time-tracking parameters
#

set TIMEPOINTS ordered;

# Each timepoint is assigned to a study period exogenously,
# so that we don't have to do any arithmetic to figure out
# which timepoint is in each period. This allows for arbitrary
# numbering of the hours, so they need not be spaced integral
# number of hours apart through the whole year. This is important
# if we want to sample, e.g., 12*24 hours per year or per 3 years.
# Another way to do it would be to exogenously specify
# how many samples there are per study period, and then bundle
# them up within the model. That would allow us to change the length
# of the study period from inside the model.
# But it wouldn't gain us very much, since the sampling must be
# done carefully for each study period anyway.

# chronological information on each timepoint (e.g. study hour, sample)
# this is used to identify which hours fall in each study period
# and how many real hours are represented by each sample (which may be fractional).
# Hour_of_day and month_of_year are just used for reporting (if that)
param period {TIMEPOINTS};
param date {TIMEPOINTS};
param hours_in_sample {TIMEPOINTS};
param hour_of_day {TIMEPOINTS};
param month_of_year {TIMEPOINTS};
param season_of_year {h in TIMEPOINTS} = floor((month_of_year[h]-1)/3)+1;

# note: periods must be evenly spaced and count by years, 
# but they can have decimals (e.g., 2006.5 for July 1, 2006)
# and be any distance apart.
# PERIODS are a synonym for PERIODS, but refer more explicitly
# the date when a power plant starts running.
set PERIODS ordered = setof {h in TIMEPOINTS} (period[h]);

# specific dates are used to collect hours that are part of the same
# day, for the purpose of hydro dispatch, etc.
set DATES ordered = setof {h in TIMEPOINTS} (date[h]);

set HOURS_OF_DAY ordered = setof {h in TIMEPOINTS} (hour_of_day[h]);
set MONTHS_OF_YEAR ordered = setof {h in TIMEPOINTS} (month_of_year[h]);
set SEASONS_OF_YEAR ordered = setof {h in TIMEPOINTS} (season_of_year[h]);

# the date (year and fraction) when the optimization starts
param start_year = first(PERIODS);

# interval between study periods
param num_years_per_period = (last(PERIODS)-first(PERIODS))/(card(PERIODS)-1);

# the first year that is beyond the simulation
# (i.e., this would be the first year of the next simulation, if there were one)
param end_year = last(PERIODS)+num_years_per_period;

# all possible years in the study
set YEARS ordered = start_year .. end_year by 1;

###############################################
#
# System loads and zones
#

# list of all load zones in the state
# it is ordered, so they are listed from north to south
set LOAD_AREAS ordered;

# load area id, useful for rapidly referencing the database
param load_area_id {LOAD_AREAS} >= 0;

# system load (MW)
param system_load {LOAD_AREAS, TIMEPOINTS} >= 0;

# Regional cost multipliers
param economic_multiplier {LOAD_AREAS} >= 0;

# system load aggregated in various ways
param total_loads_by_period {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h];
param total_loads_by_period_weighted {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h] * hours_in_sample[h];

###############################################
# Solar run parameters

# Minimum amount of electricity that solar must produce
param min_solar_production >= 0, <= 1;

# Minimum amount of electricity that solar must produce
param enable_min_solar_production >= 0, <= 1 default 0;

set SOLAR_CSP_TECHNOLOGIES;
set SOLAR_DIST_PV_TECHNOLOGIES;

###############################################
#
# Technology specifications for generators
# (most of these come from generator_info.tab)

set TECHNOLOGIES;

# database ids for technologies
param technology_id {TECHNOLOGIES} >= 0;

# list of all possible fuels
set FUELS; 

# Reference to hydro's "fuel": Water
param fuel_hydro symbolic in FUELS;

# fuel used by this type of plant
param fuel {TECHNOLOGIES} symbolic in FUELS;

# earliest time when each technology can be built
param min_build_year {TECHNOLOGIES} >= 0;

# heat rate (in MBtu/MWh)
param heat_rate {TECHNOLOGIES} >= 0;

# construction lead time (years)
param construction_time_years {TECHNOLOGIES} >= 0;

# the next six parameters decribe the fraction of costs that must be paid from the
# start of construction to the completion of the project
param year_1_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_2_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_3_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_4_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_5_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_6_cost_fraction {TECHNOLOGIES} >= 0, <= 1;

# life of the plant (age when it must be retired)
param max_age_years {TECHNOLOGIES} >= 0;

# fraction of the time when a plant will be unexpectedly unavailable
param forced_outage_rate {TECHNOLOGIES} >= 0, <= 1;

# fraction of the time when a plant must be taken off-line for maintenance
param scheduled_outage_rate {TECHNOLOGIES} >= 0, <= 1;

# does the generator have a fixed hourly capacity factor?
param intermittent {TECHNOLOGIES} binary;

# can this type of project only be installed in limited amounts?
param resource_limited {TECHNOLOGIES} binary;

# is this type of plant run in baseload mode?
param new_baseload {TECHNOLOGIES} binary;

# does this type of project have a minimum feasable installation size?
# only in place for Nuclear at the moment
# other technologies such as Coal, CSP and CCGT that hit their minimum feasable/economical size at ~100-300MW
# are left out of this constraint because the decrease in runtime is more important than added resolution on minimum install capacity,
# especially considering that if a project is economical, normally Switch will build a few hundred MW per load area
param min_build_capacity {TECHNOLOGIES} >= 0;

# the minimum capacity in MW that a project can be dispatched due to operation constraints
# (i.e. CCGTs don't operate at 5% capacity)
param min_dispatch_fraction {TECHNOLOGIES} >= 0;

# the minimum amount of hours a generator must be operating (at >= min_dispatch_fraction)
# if that generator is to be turned on at all
param min_runtime {TECHNOLOGIES} >= 0;

# the minimum amount of hours a generator must be left off before ramping up again
param min_downtime {TECHNOLOGIES} >= 0;

# the maximum ramp rate (unused at the moment)
param max_ramp_rate_mw_per_hour {TECHNOLOGIES} >= 0;

# the amount of fuel burned in MBtu that is needed to start a generator from cold
param startup_fuel_mbtu {TECHNOLOGIES} >= 0;

# Whether or not technologies located at the same place will compete for space
param technologies_compete_for_space {TECHNOLOGIES} >= 0, <= 1 default 0;

# Solar-based technologies
set SOLAR_TECHNOLOGIES = {t in TECHNOLOGIES: fuel[t]=='Solar'};

# Names of technologies that have capacity factors or maximum capacities 
# tied to specific locations. 
param tech_wind symbolic in TECHNOLOGIES;
param tech_offshore_wind symbolic in TECHNOLOGIES;
param tech_biomass_igcc symbolic in TECHNOLOGIES;
param tech_bio_gas symbolic in TECHNOLOGIES;

# names of other technologies, just to have them around 
# (but this is getting silly)
param tech_ccgt symbolic in TECHNOLOGIES;
param tech_gas_combustion_turbine symbolic in TECHNOLOGIES;

##################################################################
#
# Project data

set PROJECTS dimen 3; # Project ID, load area, technology

param project_location {PROJECTS} >= 0;
param capacity_limit {PROJECTS} >= 0;
param capacity_limit_conversion {PROJECTS} >= 0;

# cost of grid upgrades to support a new project, in dollars per peak MW.
# these are needed in order to deliver power from the interconnect point to
# the load center (or make it deliverable to other zones)
param connect_cost_per_mw {PROJECTS} >= 0 default 0;

# year for which the price of each technology has been specified
param price_and_dollar_year {PROJECTS} >= 0;

# overnight cost for the plant ($/MW)
param overnight_cost {PROJECTS} >= 0;

# fixed O&M ($/MW-year)
param fixed_o_m {PROJECTS} >= 0;

# variable O&M ($/MWh)
param variable_o_m {PROJECTS} >= 0;

# annual rate of change of overnight cost, beginning at price_and_dollar_year
param overnight_cost_change {PROJECTS};

# the nonfuel costs incurred by starting a plant from cold to producing powers
param nonfuel_startup_cost {PROJECTS};

set PROJ_RESOURCE_LIMITED = {(pid, a, t) in PROJECTS: resource_limited[t]};

# maximum capacity factors (%) for each project, each hour. 
# generally based on renewable resources available
set PROJ_INTERMITTENT_HOURS dimen 4;  # LOAD_AREAS, TECHNOLOGIES, PROJECT_ID, TIMEPOINTS
set PROJ_INTERMITTENT = setof {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS} (pid, a, t);

check: card({(pid, a, t) in PROJ_RESOURCE_LIMITED: intermittent[t]} diff PROJ_INTERMITTENT) = 0;
param cap_factor {PROJ_INTERMITTENT_HOURS};

set PROJ_ANYWHERE = {(pid, a, t) in PROJECTS: not intermittent[t] and not resource_limited[t]};

# the set of all dispatchable projects (i.e., non-intermittent)
set PROJ_DISPATCH = {(pid, a, t) in PROJECTS: not new_baseload[t] and not intermittent[t]};


# default values for projects that don't have sites
param location_unspecified symbolic;

# maximum capacity that can be installed in each project. These are units of MW for most technologies. The exceptions are Central PV and CSP, which have units of km^2 and a conversion factor of MW / km^2
set LOCATIONS_WITH_COMPETING_TECHNOLOGIES;
param capacity_limit_by_location {loc in LOCATIONS_WITH_COMPETING_TECHNOLOGIES} = min {(pid, a, t) in PROJ_RESOURCE_LIMITED: project_location[pid, a, t] == loc } capacity_limit[pid, a, t];

# make sure all hours are represented, and that cap factors make sense.
# Solar thermal can be parasitic, which means negative cap factors are allowed (just not TOO negative)
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: t in SOLAR_CSP_TECHNOLOGIES}: cap_factor[pid, a, t, h] >= -0.1;
# No other technology can be parasitic, so only positive cap factors allowed
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: not( t in SOLAR_CSP_TECHNOLOGIES) }: cap_factor[pid, a, t, h] >= 0;
# cap factors for solar can be greater than 1 becasue sometimes the sun shines more than 1000W/m^2
# which is how PV cap factors are defined.
# The below checks make sure that for other plants the cap factors
# are <= 1 but for solar they are <= 1.4
# (roughly the irradiation coming in from space, though the cap factor shouldn't ever approach this number)
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: not( t in SOLAR_TECHNOLOGIES )}: cap_factor[pid, a, t, h] <= 1;
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: t in SOLAR_TECHNOLOGIES }: cap_factor[pid, a, t, h] <= 1.4;
check {(pid, a, t) in PROJ_INTERMITTENT}: intermittent[t];


##################################################################
#
# RPS goals for each load area 
# (these come from generator_rps.tab and rps_requirement.tab)


# rps goals for each load area
param rps_compliance_percentage {LOAD_AREAS};
# What year each zone needs to meet its RPS goal
param rps_compliance_year {LOAD_AREAS};

set LOAD_AREAS_AND_FUEL_CATEGORY dimen 2;
set RPS_FUEL_CATEGORY = setof {(load_area, rps_fuel_category) in LOAD_AREAS_AND_FUEL_CATEGORY} (rps_fuel_category);
set LOAD_AREAS_WITH_RPS = setof {load_area in LOAD_AREAS: rps_compliance_percentage[load_area] > 0 } (load_area);

param enable_rps >= 0, <= 1 default 0;

# whether fuels in a load area qualify for rps 
param fuel_qualifies_for_rps {LOAD_AREAS_AND_FUEL_CATEGORY};

# determines if fuel falls in solar/wind/geo or gas/coal/nuclear/hydro
param rps_fuel_category {FUELS} symbolic in RPS_FUEL_CATEGORY;

param period_rps_takes_effect {a in LOAD_AREAS_WITH_RPS} = 
	num_years_per_period * round( ( rps_compliance_year[a] - start_year) / num_years_per_period ) + start_year;


##############################################
# Existing hydro plants (assumed impossible to build more, but these last forever)

# forced outage rate for hydroelectric dams
# this is used to de-rate the planned power production
param forced_outage_rate_hydro >= 0;

# round-trip efficiency for storing power via a pumped hydro system
param pumped_hydro_efficiency >= 0;

# annual cost for existing hydro plants (see notes in windsun.dat)
# it would be better to calculate this from the capital cost, fixed and variable O&M,
# but that introduces messy new parameters and doesn't add anything to the analysis
param hydro_capital >= 0;
param hydro_fixed_o_m >= 0;
param hydro_var_o_m >= 0;
param hydro_annual_payment_per_mw = hydro_capital + hydro_fixed_o_m + hydro_var_o_m;

# indexing sets for hydro data (read in along with data tables)
# (this should probably be monthly data, but this has equivalent effect,
# and doesn't require adding a month dataset and month <-> date links)
set PROJ_HYDRO_DATES dimen 3; # load_area, site, date

# database id for hydro projects
param hydro_project_id {PROJ_HYDRO_DATES} >= 0;
param hydro_site {PROJ_HYDRO_DATES} symbolic;

# minimum, maximum and average flow (in average MW) at each dam, each day
# (note: we assume that the average dispatch for each day must come out at this average level,
# and flow will always be between minimum and maximum levels)
# maximum is based on plant size
# average is based on historical power production for each month
# for simple hydro, minimum flow is a fixed fraction of average flow (for now)
# for pumped hydro, minimum flow is a negative value, showing the maximum pumping rate
param avg_hydro_flow {PROJ_HYDRO_DATES};
param max_hydro_flow {PROJ_HYDRO_DATES};
param min_hydro_flow {PROJ_HYDRO_DATES};
check {(a, s, d) in PROJ_HYDRO_DATES}: 
  min_hydro_flow[a, s, d] <= avg_hydro_flow[a, s, d] <= max_hydro_flow[a, s, d];
check {(a, s, d) in PROJ_HYDRO_DATES}: 
  max_hydro_flow[a, s, d] >= 0;

# list of all hydroelectric projects (pumped or simple)
set PROJ_HYDRO = setof {(a, s, d) in PROJ_HYDRO_DATES} (a, s);

set PROJ_PUMPED_HYDRO = setof {(a, s, d) in PROJ_HYDRO_DATES: min_hydro_flow[a, s, d] < 0} (a, s);
set PROJ_NONPUMPED_HYDRO = setof {(a, s, d) in PROJ_HYDRO_DATES: min_hydro_flow[a, s, d] >= 0} (a, s);


# make sure the data tables have full, matching sets of data
 check card(DATES symdiff setof {(a, s, d) in PROJ_HYDRO_DATES} (d)) = 0;
 check card(PROJ_HYDRO_DATES) = card(PROJ_HYDRO) * card(DATES);


###############################################
# Existing generators

# name of each plant
set EXISTING_PLANTS dimen 2;  # load zone, plant code

check {a in setof {(a, e) in EXISTING_PLANTS} (a)}: a in LOAD_AREAS;

# the database id of the plant
param ep_project_id {EXISTING_PLANTS} >= 0;

# the size of the plant in MW
param ep_size_mw {EXISTING_PLANTS} >= 0;

# type of technology used by the plant
param ep_technology {EXISTING_PLANTS} symbolic;

# type of fuel used by the plant
param ep_fuel {EXISTING_PLANTS} symbolic in FUELS;

# heat rate (in MBtu/MWh)
param ep_heat_rate {EXISTING_PLANTS} >= 0;

# year when the plant was built (used to calculate annual capital cost and retirement date)
param ep_vintage {EXISTING_PLANTS} >= 0;

# life of the plant (age when it must be retired)
param ep_max_age_years {EXISTING_PLANTS} >= 0;

# overnight cost of the plant ($/MW)
param ep_overnight_cost {EXISTING_PLANTS} >= 0;

# fixed O&M ($/MW-year)
param ep_fixed_o_m {EXISTING_PLANTS} >= 0;

# variable O&M ($/MWh)
param ep_variable_o_m {EXISTING_PLANTS} >= 0;

# fraction of the time when a plant will be unexpectedly unavailable
param ep_forced_outage_rate {EXISTING_PLANTS} >= 0, <= 1;

# fraction of the time when a plant must be taken off-line for maintenance
# note: this is also used for plants that only run part time
# e.g., a baseload-type plant with 97% reliability but 80% capacity factor
param ep_scheduled_outage_rate {EXISTING_PLANTS} >= 0, <= 1;

# does the generator run at its full capacity all year?
param ep_baseload {EXISTING_PLANTS} binary;

# is the generator part of a cogen facility (used for reporting)?
param ep_cogen {EXISTING_PLANTS} binary;

# is the generator intermittent (i.e. is its power production non-dispatchable)?
param ep_intermittent {EXISTING_PLANTS} binary;

###############################################
# Existing intermittent generators (existing wind, csp and pv)

# hours in which each existing intermittent renewable adds power to the grid
set EP_INTERMITTENT_HOURS dimen 3;  # load zone, plant code, hour

# capacity factor for existing intermittent renewables
# generally between 0 and 1, but for some solar plants the capacity factor may be more than 1
# due to capacity factor definition, so the limit here is 1.4
param eip_cap_factor {EP_INTERMITTENT_HOURS} >= 0 <=1.4;

###############################################
# Transmission lines

# cost to build a transmission line, per mw of capacity, per km of distance
# (assumed linear and can be added in small increments!)
param transmission_cost_per_mw_km >= 0;

# retirement age for transmission lines
param transmission_max_age_years >= 0;

# forced outage rate for transmission lines, used for probabilistic dispatch(!)
param transmission_forced_outage_rate >= 0;

# possible transmission lines are listed in advance;
# these include all possible combinations of LOAD_AREAS, with no double-counting
# The model could be simplified by only allowing lines to be built between neighboring zones.
set TRANSMISSION_LINES in {LOAD_AREAS, LOAD_AREAS};

# length of each transmission line
param transmission_length_km {TRANSMISSION_LINES};

# delivery efficiency on each transmission line
param transmission_efficiency {TRANSMISSION_LINES};

# the rating of existing lines in MW (can be different for the two directions, but each direction is
# represented by an individual entry in the table)
param existing_transfer_capacity_mw {TRANSMISSION_LINES} >= 0 default 0;

# unique ID for each transmission line, used for reporting results
param transmission_line_id {TRANSMISSION_LINES};

# parameters for local transmission and distribution from the large-scale network to distributed loads
param local_td_max_age_years >= 0;
param local_td_annual_payment_per_mw >= 0;


###################
#
# Financial data and calculations
#

# the year to which all costs should be discounted
param base_year >= 0;

# annual rate (real) to use to discount future costs to current year
param discount_rate;

# required rates of return (real) for generator and transmission investments
# may differ between generator types, and between generators and transmission lines
param finance_rate >= 0;
param transmission_finance_rate >= 0;

# cost of carbon emissions ($/ton), e.g., from a carbon tax
# can also be set negative to drive renewables out of the system
param carbon_cost;

# set and parameters used to make carbon cost curves
set CARBON_COSTS;

# annual fuel price forecast in $/MBtu
param fuel_price {LOAD_AREAS, FUELS, YEARS} default 0, >= 0;

# carbon content (tons) per MBtu of each fuel
param carbon_content {FUELS} default 0, >= 0;

# Calculate discounted fixed and variable costs for each technology and vintage

# For now, all hours in each study period use the fuel cost 
# from the year when each study period started.
# This is because we don't want artificially strong run-ups in fuel prices
# between the beginning and end of each study period as a result of the long intervals
# needed to make it solvable.
# This could be updated to use fuel costs that vary by month,
# or for an hourly model, it could interpolate between annual forecasts 
# (see versions of this model from before 11/27/07 for code to do that).
param fuel_cost_hourly {a in LOAD_AREAS, f in FUELS, h in TIMEPOINTS} := fuel_price[a, f, floor(period[h])];

# planning reserve margin - fractional extra load the system must be able able to serve
# when there are no forced outages
param planning_reserve_margin;

##########
# calculate discounted costs for new plants

# apply projected annual real cost changes to each technology,
# to get the capital, fixed and variable costs if it is installed 
# at each possible vintage date

# first, the capital cost of the plant and any 
# interconnecting lines and grid upgrades
# (all costs are in $/MW)
param capital_cost_proj {(pid, a, t) in PROJECTS, yr in PERIODS} = 
  ( overnight_cost[pid, a, t] * (1+overnight_cost_change[pid, a, t])^(yr - construction_time_years[t] - price_and_dollar_year[pid, a, t])
    + connect_cost_per_mw[pid, a, t]
  )
; 

# annual revenue that will be needed to cover the capital cost
param capital_cost_annual_payment {(pid, a, t) in PROJECTS, yr in PERIODS} = 
  finance_rate * (1 + 1/((1+finance_rate)^(max_age_years[t] + construction_time_years[t])-1)) * capital_cost_proj[pid, a, t, yr];

# date when a plant of each type and vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made) 
# until the end of that period. This avoids having artificial gaps
# between retirements and starting new plants.
param project_end_year {t in TECHNOLOGIES, yr in PERIODS} =
  min(end_year, yr+ceil(max_age_years[t]/num_years_per_period)*num_years_per_period);

# finally, take the stream of capital & fixed costs over the duration of the project,
# and discount to a lump-sum value at the start of the project,
# then discount from there to the base_year.
param fixed_cost {(pid, a, t) in PROJECTS, yr in PERIODS} = 
  # Capital payments that are paid from when construction starts till the plant is retired (or the study period ends)
  capital_cost_annual_payment[pid, a, t, yr]
    # A factor to convert Uniform annual capital payments to "Present value" in the construction year - a lump sum at the beginning of the payments. This considers the time from when construction began to the end year
    * (1-(1+discount_rate)^(-1*(project_end_year[t,yr] - yr + construction_time_years[t])))/discount_rate
    # Future value (in the construction year) to Present value (in the base year)
    * 1/(1+discount_rate)^(yr-construction_time_years[t]-base_year)
+
  # Fixed annual costs that are paid while the plant is operating (up to the end of the study period)
  fixed_o_m[pid, a, t]
    # U to P, from the time the plant comes online to the end year
    * (1-(1/(1+discount_rate)^(project_end_year[t,yr]-yr)))/discount_rate
    # F to P, from the time the plant comes online to the base year
    * 1/(1+discount_rate)^(yr-base_year);

# all variable costs ($/MWh) for generating a MWh of electricity in some
# future hour, using a particular technology and vintage, 
# discounted to reference year
# these include O&M, fuel, carbon tax
# We also multiply by the number of real hours represented by each sample,
# because a case study could use only a limited subset of hours.
# (this used to vary by vintage to allow for changing variable costs, but not anymore)
# note: in a full hourly model, this should discount each hour based on its exact date,
# but for now, since the hours are non-chronological samples within each study period,
# they are all discounted by the same factor
param variable_cost {(pid, a, t) in PROJECTS, h in TIMEPOINTS} =
  hours_in_sample[h] * (
    variable_o_m[pid, a, t] + heat_rate[t] * fuel_cost_hourly[a, fuel[t], h]
  ) * 1/(1+discount_rate)^(period[h]-base_year);

param carbon_cost_per_mwh {t in TECHNOLOGIES, h in TIMEPOINTS} = 
  hours_in_sample[h] * (
    heat_rate[t] * carbon_content[fuel[t]] * carbon_cost
  ) * 1/(1+discount_rate)^(period[h]-base_year);

########
# now get discounted costs for existing projects on similar terms

# year when the plant will be retired
# this is rounded up to the end of the study period when the retirement would occur,
# so power is generated and capital & O&M payments are made until the end of that period.
param ep_end_year {(a, e) in EXISTING_PLANTS} =
  min(end_year, start_year+ceil((ep_vintage[a, e]+ep_max_age_years[a, e]-start_year)/num_years_per_period)*num_years_per_period);

# annual revenue that is needed to cover the capital cost (per MW)
# TODO: find a better way to specify the finance rate applied to existing projects
# for now, we just assume it's the same as a new CCGT plant
# TODO: Move the regional cost adjustment into the database. 
param ep_capital_cost_annual_payment {(a, e) in EXISTING_PLANTS} = 
  finance_rate * (1 + 1/((1+finance_rate)^ep_max_age_years[a, e]-1)) * ep_overnight_cost[a, e] * economic_multiplier[a];

# discount capital costs to a lump-sum value at the start of the study.
param ep_capital_cost {(a, e) in EXISTING_PLANTS} =
# Multiply fixed costs by years per period so they will match the way multi-year periods are implicitly treated in variable costs. In variable costs, hours_in_sample is a weight intended to reflect how many hours are represented by a timepoint. hours_in_sample is calculated using period length in MySQL: period_length * (days represented) * (subsampling factors), so if you work through the math, variable costs are multiplied by period_length. A better treatment of this would be to pull period_length out of hours_in_sample and calculate the fixed & costs as the sum of annual payments that occur in a given investment year.
  ep_capital_cost_annual_payment[a, e]
    # A factor to convert Uniform annual capital payments from the start of the study until the plant is retired.
    * (1-(1/(1+discount_rate)^(ep_end_year[a, e]-start_year)))/discount_rate
    # Future value (at the start of the study) to Present value (in the base year)
    * 1/(1+discount_rate)^(start_year-base_year);
# cost per MW to operate a plant in any future period, discounted to start of study
param ep_fixed_cost {(a, e) in EXISTING_PLANTS, p in PERIODS} =
  ep_fixed_o_m[a, e] * economic_multiplier[a] 
    # A factor to convert all of the uniform annual payments that occur in a study period to the start of a study period
    * (1-(1/(1+discount_rate)^(num_years_per_period)))/discount_rate
    # Future value (at the start of the study) to Present value (in the base year)
    * 1/(1+discount_rate)^(p-base_year);

# all variable costs ($/MWh) for generating a MWh of electricity in some
# future hour, from each existing project, discounted to the reference year
param ep_variable_cost {(a, e) in EXISTING_PLANTS, h in TIMEPOINTS} =
  hours_in_sample[h] * (
    ep_variable_o_m[a, e] * economic_multiplier[a]
    + ep_heat_rate[a, e] * fuel_cost_hourly[a, ep_fuel[a, e], h]
  ) * 1/(1+discount_rate)^(period[h]-base_year);

param ep_carbon_cost_per_mwh {(a, e) in EXISTING_PLANTS, h in TIMEPOINTS} = 
  hours_in_sample[h] * (
    ep_heat_rate[a, e] * carbon_content[ep_fuel[a, e]] * carbon_cost
  ) * 1/(1+discount_rate)^(period[h]-base_year);

########
# now get discounted costs per MW for transmission lines on similar terms

# cost per MW for transmission lines
# TODO: use a transmission_annual_cost_change factor to make this vary between vintages
# TODO: Move the regional cost adjustment into the database. 
param transmission_annual_payment {(z1, z2) in TRANSMISSION_LINES, v in PERIODS} = 
  transmission_finance_rate * (1 + 1/((1+transmission_finance_rate)^transmission_max_age_years-1)) 
  * transmission_cost_per_mw_km * (economic_multiplier[z1] + economic_multiplier[z2]) / 2 * transmission_length_km[z1, z2];

# date when a transmission line built of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param transmission_end_year {v in PERIODS} =
  min(end_year, v+ceil(transmission_max_age_years/num_years_per_period)*num_years_per_period);

# discounted cost per MW
param transmission_cost_per_mw {(z1, z2) in TRANSMISSION_LINES, v in PERIODS} =
  transmission_annual_payment[z1, z2, v]
  * (1-(1/(1+discount_rate)^(transmission_end_year[v] - v)))/discount_rate
  * 1/(1+discount_rate)^(v-base_year);

# date when a when local T&D infrastructure of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param local_td_end_year {v in PERIODS} =
  min(end_year, v+ceil(local_td_max_age_years/num_years_per_period)*num_years_per_period);

# discounted cost per MW for local T&D
# note: instead of bringing in an annual payment directly (above), we could calculate it as
# = local_td_finance_rate * (1 + 1/((1+local_td_finance_rate)^local_td_max_age_years-1)) 
#  * local_td_real_cost_per_mw;
# TODO: Move the regional cost adjustment into the database. 
param local_td_cost_per_mw {v in PERIODS, a in LOAD_AREAS} = 
  local_td_annual_payment_per_mw * economic_multiplier[a]
  * (1-(1/(1+discount_rate)^(local_td_end_year[v]-v)))/discount_rate
  * 1/(1+discount_rate)^(v-base_year);

######
# total cost of existing hydro plants (including capital and O&M)
# note: it would be better to handle these costs more endogenously.
# for now, we assume the nameplate capacity of each plant is equal to its peak allowed output.

# the total cost per MW for existing hydro plants
# (the discounted stream of annual payments over the whole study)
param hydro_cost_per_mw { a in LOAD_AREAS } = 
  hydro_annual_payment_per_mw * economic_multiplier[a]
  * (1-(1/(1+discount_rate)^(end_year-start_year)))/discount_rate
  * 1/(1+discount_rate)^(start_year-base_year);
# make a guess at the nameplate capacity of all existing hydro
param hydro_total_capacity = 
  sum {(a, s) in PROJ_HYDRO} (max {(a, s, d) in PROJ_HYDRO_DATES} max_hydro_flow[a, s, d]);

######
# "discounted" system load, for use in calculating levelized cost of power.
param system_load_discounted = 
  sum {a in LOAD_AREAS, h in TIMEPOINTS} 
    (hours_in_sample[h] * system_load[a,h] 
     / (1+discount_rate)^(period[h]-base_year));

##################
# reduced sets for decision variables and constraints

# project-vintage combinations that can be installed
set PROJECT_VINTAGES = { (pid, a, t) in PROJECTS, yr in PERIODS: yr >= min_build_year[t] + construction_time_years[t]};

# project-vintage combinations that have a minimum size constraint.
set PROJ_MIN_BUILD_VINTAGES = {(pid, a, t, yr) in PROJECT_VINTAGES: min_build_capacity[t] > 0};

# technology-site-vintage-hour combinations for dispatchable projects
# (i.e., all the project-vintage combinations that are still active in a given hour of the study)
set PROJ_DISPATCH_VINTAGE_HOURS := 
  {(pid, a, t) in PROJ_DISPATCH, yr in PERIODS, h in TIMEPOINTS: not new_baseload[t] and yr >= min_build_year[t] + construction_time_years[t] and yr <= period[h] < project_end_year[t, yr]};

# technology-project-vintage-hour combinations for intermittent (non-dispatchable) projects
set PROJ_INTERMITTENT_VINTAGE_HOURS := 
  {(pid, a, t) in PROJ_INTERMITTENT, yr in PERIODS, h in TIMEPOINTS: yr >= min_build_year[t] + construction_time_years[t] and yr <= period[h] < project_end_year[t, yr]};

# plant-period combinations when new baseload plants can be installed
set NEW_BASELOAD_VINTAGES = {(pid, a, t, yr) in PROJECT_VINTAGES: new_baseload[t] and yr >= min_build_year[t] + construction_time_years[t] };

# plant-period combinations when new baseload plants can run. That is, all new baseload plants that are active in a given hour of the study
set NEW_BASELOAD_VINTAGE_HOURS =
  setof {(pid, a, t, yr) in NEW_BASELOAD_VINTAGES, h in TIMEPOINTS: yr <= period[h] < project_end_year[t, yr]} (pid, a, t, yr, h);


# plant-period combinations when existing plants can run
# these are the times when a decision must be made about whether a plant will be kept available for the year
# or mothballed to save on fixed O&M (or fuel, for baseload plants)
# note: something like this could be added later for early retirement of new plants too
set EP_PERIODS :=
  {(a, e) in EXISTING_PLANTS, yr in PERIODS: ep_vintage[a, e] <= yr < ep_end_year[a, e]};

# plant-hour combinations when existing non-baseload, non-intermittent plants can be dispatched
set EP_DISPATCH_HOURS :=
  {(a, e) in EXISTING_PLANTS, h in TIMEPOINTS: not ep_baseload[a, e] and not ep_intermittent[a,e] and ep_vintage[a, e] <= period[h] < ep_end_year[a, e]};

# plant-hour combinations when existing intermittent plants can produce power or be mothballed (e.g. They have not been retired yet)
set EP_INTERMITTENT_OPERATIONAL_HOURS :=
  {(a, e, h) in EP_INTERMITTENT_HOURS: 
  	# Retire plants after their max age. e.g. Filter out periods that occur before the plant "is built" and periods that occur after the plant is retired. 
  	ep_vintage[a, e] <= period[h] < ep_end_year[a, e]};

# plant-period combinations when existing baseload plants can run
# should this be as above limiting periods to times at which the plant hasn't retired yet?
set EP_BASELOAD_PERIODS :=
  {(a, e, yr) in EP_PERIODS: ep_baseload[a, e]};

# trans_line-vintage-hour combinations for which dispatch decisions must be made
set TRANS_VINTAGE_HOURS := 
  {(z1, z2) in TRANSMISSION_LINES, yr in PERIODS, h in TIMEPOINTS: yr <= period[h] < transmission_end_year[yr]};

# local_td-vintage-hour combinations which must be reconciled
set LOCAL_TD_HOURS := 
  {a in LOAD_AREAS, yr in PERIODS, h in TIMEPOINTS: yr <= period[h] < local_td_end_year[yr]};


#### VARIABLES ####

# number of MW to install in each project at each date (vintage)
var InstallGen {PROJECT_VINTAGES} >= 0;

# binary constraint that restricts small plants of certain types of generators (ex: Nuclear) from being built
# this quantity is one when there is there is not a constraint on how small plants can be
# and is zero when there is a constraint
#var BuildGenOrNot {PROJ_MIN_BUILD_VINTAGES} >= 0, <= 1; 
var BuildGenOrNot {PROJ_MIN_BUILD_VINTAGES} binary;

# number of MW to generate from each project, in each hour
var DispatchGen {PROJ_DISPATCH, TIMEPOINTS} >= 0;

# share of existing plants to operate during each study period.
# this should be a binary variable, but it's interesting to see 
# how the continuous form works out
#var OperateEPDuringPeriod {EP_PERIODS} >= 0, <= 1;
var OperateEPDuringPeriod {EP_PERIODS} binary;

# number of MW to generate from each existing dispatchable plant, in each hour
var DispatchEP {EP_DISPATCH_HOURS} >= 0;

# number of MW to install in each transmission corridor at each vintage
var InstallTrans {TRANSMISSION_LINES, PERIODS} >= 0;

# number of MW to transmit through each transmission corridor in each hour
var DispatchTransFromXToY {TRANSMISSION_LINES, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var DispatchTransFromXToY_Reserve {TRANSMISSION_LINES, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;

# amount of local transmission and distribution capacity
# (to carry peak power from transmission network to distributed loads)
var InstallLocalTD {LOAD_AREAS, PERIODS} >= 0;

# amount of pumped hydro to store and dispatch during each hour
# note: the amount "stored" is the number of MW that can be generated using
# the water that is stored, 
# so it takes 1/pumped_hydro_efficiency MWh to store 1 MWh
var StorePumpedHydro {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var DispatchHydro {PROJ_HYDRO, TIMEPOINTS} >= 0;
var StorePumpedHydro_Reserve {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var DispatchHydro_Reserve {PROJ_HYDRO, TIMEPOINTS} >= 0;

#### OBJECTIVES ####

# total cost of power, including carbon tax
# a = Load Area
# t = technology
# s = site
# o = orientation (PV tilt, usually not used)
# p = PERIODS, the start of an investment period as well as the date when a power plant starts running.
# h = study hour - unique timepoint considered
# e = Plant ID for existing plants. In US, this is the FERC plant_code. e.g. 55306-CC
# p = investment period
minimize Power_Cost:

	#############################
	#    NEW PLANTS
  # Calculate fixed costs for all new plants
    sum {(pid, a, t, yr) in PROJECT_VINTAGES} 
      InstallGen[pid, a, t, yr] * fixed_cost[pid, a, t, yr]
  # Calculate variable costs for new plants that are dispatchable. 
  + sum {(pid, a, t) in PROJ_DISPATCH, h in TIMEPOINTS} 
      DispatchGen[pid, a, t, h] * (variable_cost[pid, a, t, h] + carbon_cost_per_mwh[t, h])
  # Calculate variable costs for new baseload plants for all the hours in which they will operate
  + sum {(pid, a, t, yr, h) in NEW_BASELOAD_VINTAGE_HOURS}
      (1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[pid, a, t, yr] 
      * (variable_cost[pid, a, t, h] + carbon_cost_per_mwh[t, h])

	#############################
	#    EXISTING PLANTS
  # Calculate capital costs for all existing plants. This number is not affected by any of the decision variables because it is a sunk cost.
  + sum {(a, e) in EXISTING_PLANTS}
      ep_size_mw[a, e] * ep_capital_cost[a, e]
  # Calculate fixed costs for all existing plants
  + sum {(a, e, p) in EP_PERIODS} 
      OperateEPDuringPeriod[a, e, p] * ep_size_mw[a, e] * ep_fixed_cost[a, e, p]
  # Calculate variable costs for existing BASELOAD plants
  # NOTE: The number of decision variables could be reduced significantly if you indexed ep_variable_cost & ep_carbon_cost_per_mwh by p instead of h, then express the sum like this: + sum {(a, e, p) in EP_BASELOAD_PERIODS} OperateEPDuringPeriod[a, e, p] * (1-ep_forced_outage_rate[a, e]) * (1-ep_scheduled_outage_rate[a, e]) * ep_size_mw[a, e] * (ep_variable_cost[a, e, p] + ep_carbon_cost_per_mwh[a, e, p]) * total_hours_in_period[p]
  + sum {(a, e, p) in EP_BASELOAD_PERIODS, h in TIMEPOINTS: period[h]=p}
      OperateEPDuringPeriod[a, e, p] * (1-ep_forced_outage_rate[a, e]) * (1-ep_scheduled_outage_rate[a, e]) * ep_size_mw[a, e] 
      * (ep_variable_cost[a, e, h] + ep_carbon_cost_per_mwh[a, e, h])
  # Calculate variable costs for existing NON-BASELOAD plants
  + sum {(a, e, h) in EP_DISPATCH_HOURS}
      DispatchEP[a, e, h]
      * (ep_variable_cost[a, e, h] + ep_carbon_cost_per_mwh[a, e, h])
  # Calculate variable costs for existing INTERMITTENT plants
  + sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS}
      OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * eip_cap_factor[a, e, h] * 
      (1-ep_forced_outage_rate[a, e]) * ep_variable_cost[a, e, h]

  # Hydro
  + sum {(a, s) in PROJ_HYDRO} 
      hydro_cost_per_mw[a] * (max {(a, s, d) in PROJ_HYDRO_DATES} max_hydro_flow[a, s, d])

	########################################
	#    TRANSMISSION & DISTRIBUTION
  + sum {(z1, z2) in TRANSMISSION_LINES, v in PERIODS} 
      InstallTrans[z1, z2, v] * transmission_cost_per_mw[z1, z2, v]
  + sum {(z1, z2) in TRANSMISSION_LINES} 
      transmission_cost_per_mw[z1, z2, first(PERIODS)] * (existing_transfer_capacity_mw[z1, z2])/2
  + sum {a in LOAD_AREAS, v in PERIODS}
      InstallLocalTD[a, v] * local_td_cost_per_mw[v, a]
;

# this alternative objective is used to reduce transmission flows to
# zero in one direction of each pair, and to minimize needless flows
# around loops, or shipping of unneeded power to neighboring zones, 
# so it is more clear where surplus power is being generated
minimize Transmission_Usage:
  sum {(z1, z2) in TRANSMISSION_LINES, h in TIMEPOINTS, fuel_cat in RPS_FUEL_CATEGORY} 
    (DispatchTransFromXToY[z1, z2, h, fuel_cat]);


#### CONSTRAINTS ####

# system needs to meet the load in each load zone in each hour
# note: power is deemed to flow from z1 to z2 if positive, reverse if negative
subject to Satisfy_Load {a in LOAD_AREAS, h in TIMEPOINTS}:

	#############################
	#    NEW PLANTS
  # new dispatchable projects
  (sum {(pid, a, t) in PROJ_DISPATCH} DispatchGen[pid, a, t, h])
  # output from new intermittent projects
  + (sum {(pid, a, t, yr, h) in PROJ_INTERMITTENT_VINTAGE_HOURS} 
      (1-forced_outage_rate[t]) * cap_factor[pid, a, t, h] * InstallGen[pid, a, t, yr])
  # new baseload plants
  + sum {(pid, a, t, yr, h) in NEW_BASELOAD_VINTAGE_HOURS} 
      ((1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[pid, a, t, yr] )

	#############################
	#    EXISTING PLANTS
  # existing baseload plants
  + sum {(a, e, p) in EP_BASELOAD_PERIODS: p=period[h]} 
      (OperateEPDuringPeriod[a, e, p] * (1-ep_forced_outage_rate[a, e]) * (1-ep_scheduled_outage_rate[a, e]) * ep_size_mw[a, e])
  # existing dispatchable plants
  + sum {(a, e, h) in EP_DISPATCH_HOURS} DispatchEP[a, e, h]
  # existing intermittent plants
  + sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS} 
      OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * eip_cap_factor[a, e, h] * (1-ep_forced_outage_rate[a, e])

  # pumped hydro, de-rated to reflect occasional unavailability of the hydro plants
  + (1 - forced_outage_rate_hydro) * (sum {(a, s) in PROJ_HYDRO} DispatchHydro[a, s, h])
  - (1 - forced_outage_rate_hydro) * (1/pumped_hydro_efficiency) * 
      (sum {(a, s) in PROJ_PUMPED_HYDRO} StorePumpedHydro[a, s, h])


	########################################
	#    TRANSMISSION
  # transmission into and out of the zone. 
  
  # Transmitted power coming into the zone will have losses because of the transmission line it has come in over;
  # as a result, the incoming DispatchTransFromXToY[z2, a, h, ft] is multiplied by the transmission efficiency of the line over which it was transmitted.
  # On the other hand, transmitted power leaving the zone will not yet have experienced transmission losses; as a result the outgoing 
  # DispatchTransFromXToY[a, z1, h, ft] is not multiplied by the transmission efficiency.

  # Imports (have experienced transmission losses)
  + (sum {(z2, a) in TRANSMISSION_LINES, fc in RPS_FUEL_CATEGORY} (transmission_efficiency[z2, a] * DispatchTransFromXToY[z2, a, h, fc]))
  
  # Exports (have not experienced transmission losses)
  - (sum {(a, z1) in TRANSMISSION_LINES, fc in RPS_FUEL_CATEGORY} (DispatchTransFromXToY[a, z1, h, fc]))

  >= system_load[a, h];

################################################################################
# same on a reserve basis
# note: these are not prorated by forced outage rate, because that is incorporated in the reserve margin
subject to Satisfy_Load_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:

	#############################
	#    NEW PLANTS
  # new dispatchable capacity (no need to decide how to dispatch it; we just need to know it's available)
  (sum {(pid, a, t, yr, h) in PROJ_DISPATCH_VINTAGE_HOURS} InstallGen[pid, a, t, yr])

  # Is it appropriate to put intermittent plants into the load reserve? Do any utility regulators currently allow this?
  # output from new intermittent projects
  + (sum {(pid, a, t, yr, h) in PROJ_INTERMITTENT_VINTAGE_HOURS} 
      cap_factor[pid, a, t, h] * InstallGen[pid, a, t, yr])

  # new baseload plants
  + sum {(pid, a, t, yr, h) in NEW_BASELOAD_VINTAGE_HOURS} 
      ((1-scheduled_outage_rate[t]) * InstallGen[pid, a, t, yr] )

	#############################
	#    EXISTING PLANTS
  # existing baseload plants
  + sum {(a, e, p) in EP_BASELOAD_PERIODS: p=period[h]} 
      (OperateEPDuringPeriod[a, e, p] * (1-ep_scheduled_outage_rate[a, e]) * ep_size_mw[a, e])
  # existing dispatchable capacity
  + sum {(a, e, h) in EP_DISPATCH_HOURS} OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e]
  # existing intermittent plants
  + sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS} 
      OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * eip_cap_factor[a, e, h]

  # Hydro
  + (sum {(a, s) in PROJ_HYDRO} DispatchHydro_Reserve[a, s, h])
  - (1/pumped_hydro_efficiency) * 
      (sum {(a, s) in PROJ_PUMPED_HYDRO} StorePumpedHydro_Reserve[a, s, h])

	########################################
	#    TRANSMISSION
  # Imports (have experienced transmission losses)
  + (sum {(z2, a) in TRANSMISSION_LINES, fc in RPS_FUEL_CATEGORY} (transmission_efficiency[z2, a] * DispatchTransFromXToY_Reserve[z2, a, h, fc]))
  # Exports (have not experienced transmission losses)
  - (sum {(a, z1) in TRANSMISSION_LINES, fc in RPS_FUEL_CATEGORY} (DispatchTransFromXToY_Reserve[a, z1, h, fc]))

  >= system_load[a, h] * (1 + planning_reserve_margin);


################################################################################
# pumped hydro dispatch for all hours of the day must be within the limits of the plant
# net flow of power (i.e., water) must also match the historical average
# TODO: find better historical averages that reflect net balance of generated and stored power,
#  because the values currently used are equal to sum(Dispatch - 1/efficiency * Storage)

# All hydro is subject to max flow constraints
subject to Maximum_DispatchHydro {(a, s) in PROJ_HYDRO, h in TIMEPOINTS}:
  DispatchHydro[a, s, h] <= max_hydro_flow[a, s, date[h]];

# Min flow for non-pumped hydro
subject to Minimum_DispatchNonPumpedHydro {(a, s) in PROJ_NONPUMPED_HYDRO, h in TIMEPOINTS}:
  DispatchHydro[a, s, h] >= min_hydro_flow[a, s, date[h]];
# Pumped hydro storage
subject to Maximum_StorePumpedHydro {(a, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
  StorePumpedHydro[a, s, h] <= -min_hydro_flow[a, s, date[h]];
  
# Average flow for pumped & standard hydro
subject to Average_PumpedHydroFlow {(a, s) in PROJ_PUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} (DispatchHydro[a, s, h] - StorePumpedHydro[a, s, h]) <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_flow[a, s, d];
subject to Average_HydroFlow {(a, s) in PROJ_NONPUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} DispatchHydro[a, s, h] <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_flow[a, s, d];


# same for reserve margin operation
subject to Maximum_DispatchHydro_Reserve {(a, s) in PROJ_HYDRO, h in TIMEPOINTS}:
  DispatchHydro_Reserve[a, s, h] <= max_hydro_flow[a, s, date[h]];

subject to Minimum_DispatchHydro_Reserve {(a, s) in PROJ_NONPUMPED_HYDRO, h in TIMEPOINTS}:
  DispatchHydro_Reserve[a, s, h] >= min_hydro_flow[a, s, date[h]];
subject to Maximum_StorePumpedHydro_Reserve {(a, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
  StorePumpedHydro_Reserve[a, s, h] <= -min_hydro_flow[a, s, date[h]];

subject to Average_PumpedHydroFlow_Reserve {(a, s) in PROJ_PUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} (DispatchHydro_Reserve[a, s, h] - StorePumpedHydro_Reserve[a, s, h]) <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_flow[a, s, d];
subject to Average_HydroFlow_Reserve {(a, s) in PROJ_NONPUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} DispatchHydro_Reserve[a, s, h] <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_flow[a, s, d];


# system can only dispatch as much of each project as is EXPECTED to be available
# i.e., we only dispatch up to 1-forced_outage_rate, so the system will work on an expected-value basis
# (this is the base portfolio, more backup generators will be added later to get a lower year-round risk level)
subject to Maximum_DispatchGen 
  {(pid, a, t) in PROJ_DISPATCH, h in TIMEPOINTS}:
  DispatchGen[pid, a, t, h] <= (1-forced_outage_rate[t]) * 
    sum {(pid, a, t, yr, h) in PROJ_DISPATCH_VINTAGE_HOURS} InstallGen[pid, a, t, yr];

# there are limits on total installations in certain projects
# TODO: adjust this to allow re-installing at the same site after retiring an earlier plant
# (not an issue if the simulation is too short to retire plants)
# or even allow forced retiring of earlier plants if new technologies are better
subject to Maximum_Resource_Competing_Tech {l in LOCATIONS_WITH_COMPETING_TECHNOLOGIES}:
  sum {yr in PERIODS, (pid, a, t) in PROJ_RESOURCE_LIMITED: 
         yr >= min_build_year[t] + construction_time_years[t] and project_location[pid, a, t] = l} 
  	InstallGen[pid, a, t, yr] / capacity_limit_conversion[pid, a, t] 
  	<= capacity_limit_by_location[l];

subject to Maximum_Resource_Location_Unspecified { (pid, a, t) in PROJ_RESOURCE_LIMITED: not( project_location[pid, a, t] in LOCATIONS_WITH_COMPETING_TECHNOLOGIES ) }:
  sum {yr in PERIODS: yr >= min_build_year[t] + construction_time_years[t]} 
  	InstallGen[pid, a, t, yr] / capacity_limit_conversion[pid, a, t] <= capacity_limit[pid, a, t];


# Some generators have a minimum build size. This enforces that constraint
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be >= min_build_capacity
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen has to be >= 0
subject to Minimum_GenSize 
  {(pid, a, t, yr) in PROJ_MIN_BUILD_VINTAGES}:
  InstallGen[pid, a, t, yr] >= min_build_capacity[t] * BuildGenOrNot[pid, a, t, yr];

# This binds BuildGenOrNot to InstallGen. The number below (1e6) is somewhat arbitrary. 
# I picked a number that would be far above the largest generator that would possibly be built
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be <= 0
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen can be between 0 & 1e6 - basically no upper limit
subject to BuildGenOrNot_Constraint 
  {(pid, a, t, yr) in PROJ_MIN_BUILD_VINTAGES}:
  InstallGen[pid, a, t, yr] <= 1000000 * BuildGenOrNot[pid, a, t, yr];

# existing dispatchable plants can only be used if they are operational this year
subject to EP_Operational
  {(a, e, h) in EP_DISPATCH_HOURS}: DispatchEP[a, e, h] <= 
      OperateEPDuringPeriod[a, e, period[h]] * (1-ep_forced_outage_rate[a, e]) * ep_size_mw[a, e];

# system can only use as much transmission as is expected to be available
# note: transmission up and down the line both enter positively,
# but the form of the model allows them to both be reduced or increased by a constant,
# so they will both be held low enough to stay within the installed capacity
# (if there were a variable cost of operating, one of them would always go to zero)
# a quick follow-up model run minimizing transmission usage will push one of these to zero.
# TODO: retire pre-existing transmission lines after transmission_max_age_years 
#   (this requires figuring out when they were first built!)
subject to Maximum_DispatchTransFromXToY
  {(z1, z2) in TRANSMISSION_LINES, h in TIMEPOINTS}:
  ( sum { fc in RPS_FUEL_CATEGORY } DispatchTransFromXToY[z1, z2, h, fc] )
    <= (1-transmission_forced_outage_rate) * 
          (existing_transfer_capacity_mw[z1, z2] + sum {(z1, z2, v, h) in TRANS_VINTAGE_HOURS} InstallTrans[z1, z2, v]);

# Simple fix to problem of asymetrical transmission build-out
subject to SymetricalTrans
  {(z1, z2) in TRANSMISSION_LINES, p in PERIODS}: InstallTrans[z1, z2, p] == InstallTrans[z2, z1, p];

subject to Maximum_DispatchTransFromXToY_Reserve
  {(z1, z2) in TRANSMISSION_LINES, h in TIMEPOINTS}:
  ( sum { fc in RPS_FUEL_CATEGORY } DispatchTransFromXToY_Reserve[z1, z2, h, fc] )
    <= (existing_transfer_capacity_mw[z1, z2] + sum {(z1, z2, v, h) in TRANS_VINTAGE_HOURS} InstallTrans[z1, z2, v]);


# make sure there's enough intra-zone transmission and distribution capacity
# to handle the net distributed loads
subject to Maximum_LocalTD 
  {a in LOAD_AREAS, h in TIMEPOINTS}:
  system_load[a,h]
    # New distributed PV
    - (sum {(pid, a, t, yr, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES}
        (1-forced_outage_rate[t]) * cap_factor[pid, a, t, h] * InstallGen[pid, a, t, yr])
    # Existing distributed PV
    - (sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: ep_technology[a,e] in SOLAR_DIST_PV_TECHNOLOGIES }
    	OperateEPDuringPeriod[a, e, period[h]] * 
        (1-ep_forced_outage_rate[a,e]) * eip_cap_factor[a, e, h] * ep_size_mw[a, e] )
  <= sum {(a, yr, h) in LOCAL_TD_HOURS} InstallLocalTD[a, yr];


#################################################
# Constraint: Min_Gen_Fraction_From_Solar
# The sum of system-wide power output by new and existing solar plants in the last investment period 
# (weighted by hours in each timepoint) must be greater than or equal to the policy target 
# (expressed as a fraction of system load)
#
# Note, by default windsun.run will drop this constraint. Set enable_min_solar_production to 1 to enable this constraint.
subject to Min_Gen_Fraction_From_Solar:
    # New solar plants power output in the last periods
	(sum {(pid, a, t, yr, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: 
	      t in SOLAR_TECHNOLOGIES and yr = last( PERIODS ) } 
        (1-forced_outage_rate[t]) * cap_factor[pid, a, t, h] * InstallGen[pid, a, t, yr] * hours_in_sample[h]) 
    # Existing solar plants power output in the last periods
    + (sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: 
        ep_technology[a,e] in SOLAR_TECHNOLOGIES and period[h] = last( PERIODS ) }
    	OperateEPDuringPeriod[a, e, period[h]] * 
        (1-ep_forced_outage_rate[a,e]) * eip_cap_factor[a, e, h]  * ep_size_mw[a, e] * hours_in_sample[h] )
    # The policy target expressed as a fraction of total load in the last period
    >=  min_solar_production * total_loads_by_period_weighted[ last( PERIODS ) ];

#################################################
# RPS constraint
# windsun.run will drop this constraint if enable_rps is 0 (its default value)
subject to Satisfy_RPS {a in LOAD_AREAS_WITH_RPS, yr in PERIODS: 
	yr >= period_rps_takes_effect[a] }:

 (
	#############################
	#   Power from NEW PLANTS
  # new dispatchable projects
   (sum {(pid, a, t) in PROJ_DISPATCH, h in TIMEPOINTS: 
        period[h] = yr and fuel_qualifies_for_rps[a, rps_fuel_category[fuel[t]]]} 
     DispatchGen[pid, a, t, h] * hours_in_sample[h]
   )
  # output from new intermittent projects
  + (sum {(pid, a, t, install_year, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: 
          period[h] = yr and fuel_qualifies_for_rps[a, rps_fuel_category[fuel[t]]]} 
      (1-forced_outage_rate[t]) * cap_factor[pid, a, t, h] * InstallGen[pid, a, t, install_year] * hours_in_sample[h]
    )
  # new baseload plants
  + (sum {(pid, a, t, install_year, h) in NEW_BASELOAD_VINTAGE_HOURS: 
          period[h] = yr and fuel_qualifies_for_rps[a, rps_fuel_category[fuel[t]]]} 
      (1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[pid, a, t, install_year] * hours_in_sample[h]
    )

	#############################
	#    Power from EXISTING PLANTS
  # existing baseload plants
  + (sum {(a, e, yr) in EP_BASELOAD_PERIODS, h in TIMEPOINTS: 
          period[h]=yr and fuel_qualifies_for_rps[a, rps_fuel_category[ep_fuel[a,e]]]} 
      OperateEPDuringPeriod[a, e, yr] * (1-ep_forced_outage_rate[a, e]) * (1-ep_scheduled_outage_rate[a, e]) * ep_size_mw[a, e] * hours_in_sample[h]
    )
  # existing dispatchable plants
  + (sum {(a, e, h) in EP_DISPATCH_HOURS: 
          period[h]=yr and fuel_qualifies_for_rps[a, rps_fuel_category[ep_fuel[a,e]]]} 
      DispatchEP[a, e, h] * hours_in_sample[h]
    )
  # existing intermittent plants
  + (sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: 
          period[h]=yr and fuel_qualifies_for_rps[a, rps_fuel_category[ep_fuel[a,e]]]} 
      OperateEPDuringPeriod[a, e, yr] * ep_size_mw[a, e] * eip_cap_factor[a, e, h] * (1-ep_forced_outage_rate[a, e]) * hours_in_sample[h]
    )

	########################################
	#    TRANSMISSION
  # transmission into and out of the zone.

#  Imports
  + (sum {(z2, a) in TRANSMISSION_LINES, fc in RPS_FUEL_CATEGORY, h in TIMEPOINTS: 
          period[h]=yr and fuel_qualifies_for_rps[a, fc]}
      (transmission_efficiency[z2, a] * DispatchTransFromXToY[z2, a, h, fc]) * hours_in_sample[h]
    )
  
#  Exports
  - (sum {(a, z1) in TRANSMISSION_LINES, fc in RPS_FUEL_CATEGORY, h in TIMEPOINTS: 
          period[h]=yr and fuel_qualifies_for_rps[a, fc]}
      DispatchTransFromXToY[a, z1, h, fc] * hours_in_sample[h]
    )
 ) 
  / (sum { h in TIMEPOINTS: 
           period[h] = yr } 
      system_load[a, h] * hours_in_sample[h]
    )
  >= rps_compliance_percentage[a];

#############################
# REC accounting: Reclassifying electrons is verboten!
# windsun.run will drop this constraint if enable_rps is 0 (its default value)
subject to Conservation_of_Colored_Electrons {a in LOAD_AREAS, h in TIMEPOINTS, ft in RPS_FUEL_CATEGORY }:

	#############################
	#    Power Production
  # new dispatchable projects
    (sum {(pid, a, t) in PROJ_DISPATCH: rps_fuel_category[fuel[t]] = ft} 
      DispatchGen[pid, a, t, h]
    )
  # new intermittent projects
  + (sum {(pid, a, t, install_year, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: rps_fuel_category[fuel[t]] = ft} 
      (1-forced_outage_rate[t]) * cap_factor[pid, a, t, h] * InstallGen[pid, a, t, install_year]
    )
  # new baseload plants
  + (sum {(pid, a, t, install_year, h) in NEW_BASELOAD_VINTAGE_HOURS: rps_fuel_category[fuel[t]] = ft} 
      (1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[pid, a, t, install_year] 
    )
  # existing baseload plants
  + (sum {(a, e, p) in EP_BASELOAD_PERIODS: p=period[h] and rps_fuel_category[ep_fuel[a,e]] = ft} 
      OperateEPDuringPeriod[a, e, p] * (1-ep_forced_outage_rate[a, e]) * (1-ep_scheduled_outage_rate[a, e]) * ep_size_mw[a, e]
    )
  # existing dispatchable plants
  + (sum {(a, e, h) in EP_DISPATCH_HOURS: rps_fuel_category[ep_fuel[a,e]] = ft} 
      DispatchEP[a, e, h]
    )
  # existing intermittent plants
  + (sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: rps_fuel_category[ep_fuel[a,e]] = ft} 
      OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * eip_cap_factor[a, e, h] * (1-ep_forced_outage_rate[a, e])
    )

  #############################
  # Imports (have experienced transmission losses)
  + (sum {(z2, a) in TRANSMISSION_LINES} 
      transmission_efficiency[z2, a] * DispatchTransFromXToY[z2, a, h, ft]
    )
  
     #############################
     # Exports (have not experienced transmission losses)
  >= (sum {(a, z1) in TRANSMISSION_LINES} (DispatchTransFromXToY[a, z1, h, ft]));


#######
# REC accounting: Reclassifying electrons is verboten!
# Hydro power production is done differently than all the other technologies
# Consequently, we need to express it in a separate constraint instead of bundling it into the one above. 
# windsun.run will drop this constraint if enable_rps is 0 (its default value)
subject to Conservation_of_Blue_Electrons {a in LOAD_AREAS, h in TIMEPOINTS}:

  ####
  # Hydro Production
  # pumped hydro, de-rated to reflect occasional unavailability of the hydro plants
  + (1 - forced_outage_rate_hydro) * (sum {(a, s) in PROJ_HYDRO} DispatchHydro[a, s, h])
  - (1 - forced_outage_rate_hydro) * (1/pumped_hydro_efficiency) * 
      (sum {(a, s) in PROJ_PUMPED_HYDRO} StorePumpedHydro[a, s, h])

  # Imports (have experienced transmission losses)
  + (sum {(z2, a) in TRANSMISSION_LINES} (transmission_efficiency[z2, a] * DispatchTransFromXToY[z2, a, h, rps_fuel_category[fuel_hydro]]))
  
     # Exports (have not experienced transmission losses)
  >= (sum {(a, z1) in TRANSMISSION_LINES} (DispatchTransFromXToY[a, z1, h, rps_fuel_category[fuel_hydro] ]));
