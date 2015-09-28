/* 	To gather some information on hedge funds that has been relauched
*/
	
* Program Version 0.1
* Last update 07/Feb/2015

clear 														// Leave matrix uncleared
clear mata
macro drop _all
program drop _all
set varabbrev off

****************** Program Settings ******************
global Folder 		= "D:\Dropbox\Projects\2015 - Lippers Tass Relaunched Hedge Funds"		// Location of program scripts
global Data 		= "D:\Workspace\Temp"								// Location to which temporary files are generated
global DataSource  	= "D:\Dropbox\Resources\Datasets\Lippers Tass\Tass_Access_13"		// Location of the original data files (ASCII)
******************************************************

* PROGRAM STARTS FROM HERE *

* Other environmental variables
cap set procs_use 4
cap set memory 12g
#delimit cr
set trace off
set more off
cap set maxvar 20000
cap set matsize 11000
set scrollbufsize 2048000
set dp period
set scheme s1color
set printcolor automatic
set copycolor automatic
set autotabgraphs on
set level 95
set maxiter 16000
set varabbrev off
set reventries 32000
*set maxdb 500
set seed 999						
set type double
set logtype text
pause on
*sysdir set PERSONAL "$Data\ado"
*sysdir set PLUS "$Data\ado\plus"
*sysdir set OLDPLACE "$Data\ado" 
*net set ado PERSONAL
set rmsg on
cd "$Folder"

disp "dateTime: $S_DATE $S_TIME"

cap program drop fundCount
program fundCount
qui {
	* calculate the number of funds
	bysort ProductReference: gen dup = _n
	replace dup = 0 if dup>1
	egen numberOfFunds = total(dup)
	sum numberOfFunds
	global fundNumber = r(mean)

	* live funds v.s. graveyard funds
	// use PerformanceEndDate to identify dead funds
	format PerformanceEndDate %tc
	
	cap gen daySep2013 = mofd(mdy(09, 30, 2013))
	cap gen endDate = mofd(dofc(PerformanceEndDate))
	cap gen liveFund = daySep2013<=endDate

	count if liveFund==1 & dup==1
	}
	qui count	
	disp "In total there is " $fundNumber " funds and " r(N) " observations in the dataset."
	*disp r(N) " out of " $fundNumber " funds are live, and the remaining " $fundNumber - r(N) " funds are dead."
	* number of observations in the dataset

	*sum liveFund
	drop dup numberOfFunds
end program


******************************************************
****************** S1. Prepare Data ******************
******************************************************
*S1.2 Preapare dataset
	// Load manager details
	use "$DataSource\\PeopleDetails.dta", clear
	keep if PersonTypeID==1
	keep ProductReference PersonID First Last JobTitle Address1 Address2 Address3 CityName StateName Zip CountryName
	save "$Data\\managers.dta", replace
	
	// Extract Inception/PerformanceEndData date from ProductDetails
	use "$DataSource\\ProductDetails.dta", clear
	keep ProductReference InceptionDate PerformanceEndDate
	save "$Data\\dates.dta", replace
	
	
******************************************************
****************** S2. Preliminary Analysis **********
******************************************************	
	// Merge Managers with the start/end dates
	use "$Data\\managers.dta", clear
	merge m:1 ProductReference using "$Data\\dates.dta"
	disp "non-matches are excluded."
	keep if _merge==3
	drop _merge
	
	// Convert datatime to %td
	local vars = "PerformanceEndDate InceptionDate" 
	foreach x of local vars {
		gen double tmp = dofc(`x')
		drop `x'
		rename tmp `x'
		format `x' %td
	}
	
	// Find managers with gaps during managing funds
	sort PersonID PerformanceEndDate InceptionDate ProductReference
	order PersonID PerformanceEndDate InceptionDate ProductReference

	// ProductReference is the identifier
	by PersonID: gen first_end_date = PerformanceEndDate[1]
	format first_end_date %tc
	
	sort PersonID InceptionDate PerformanceEndDate ProductReference

	
*S2.2 Check duration gaps using a complex loop
	sort PersonID InceptionDate PerformanceEndDate ProductReference
	global maxRows = _N
	local current_person = -999
	local current_hf = -999
	gen gap = .
	gen rolling_date = .
	format rolling_date %tc
	
	
	order gap rolling_date
	forvalues currentRow = 1/$maxRows {
		if `current_person' ~= PersonID[`currentRow'] {
	        // Move to a new stock now
            // Reset all variables
			local current_person = PersonID[`currentRow']
			local current_hf = ProductReference[`currentRow']
			local first_end_date = first_end_date[`currentRow']
			local last_end_date = first_end_date[`currentRow']
			
			mkmat InceptionDate PerformanceEndDate if PersonID==`current_person', matrix(mat_date) 

			local r = rowsof(mat_date)
			
			*matrix list mat_date 

			forvalues i = 1/`r' { 
				// start to compare ith row
				scalar is_gap = -99
				
				forvalues k = 1/`r' {	// 3 is the last row
					if `i'~=`k' {
						// define the cut-off starting date
						// i.e. 6 months (182 days) prior to the start of the gap fund
						
						local start_gap = mdy(month(mat_date[`i',1]), day(mat_date[`i',1]), year(mat_date[`i',1])) ///
							- 182
						
						if (`start_gap'>mat_date[`k',1] & `start_gap'>mat_date[`k',2]) {
							if is_gap==-99 {
								scalar is_gap = 1
							}
						}
						else if (mat_date[`i',1]<mat_date[`k',1] & mat_date[`i',1]<mat_date[`k',2])  {
							if is_gap==-99 {
								scalar is_gap = 0
							}	
						
						}
						else {
							scalar is_gap = 0
						}
					
					}
				
				}
				local new_row = `currentRow' + `i' - 1
				
				qui replace gap = is_gap in `new_row'


			}
			
			*disp is_gap
		}
		
		// check if there is a gap
		// No Gap
		*1: Inc---------End
		*2:        Inc---------End
		
		
		// No Gap
		*1: Inc---------------------End
		*2:        Inc---------End	
		
		// Gap
		*1: Inc--------End
		*2:                   Inc---------End			
		*3:                        Inc-----------End
		
		// Do pairwise comparison:
		// Each Inc is compared to all (Inc, End) of all other funds
		// If Inc < a (End) and Inc> a (Inc) --> No Gap
		// If Inc> all (Inc, End) --> Gap
	
		
		disp "Now inspecting row `currentRow' out of total " $maxRows " rows."
	}
	
	// Generate gap2 for if funds' inception data is later than gap
	gen tmp = InceptionDate if gap==1
	by PersonID: egen min_tmp = min(tmp)
	gen gap2 = InceptionDate>=min_tmp
	drop tmp min_tmp
	
	disp "gap Definition: -99 = 1 fund per person; 0 = no gap; 1 = gap"
	tab gap
	order PersonID ProductReference gap gap2 InceptionDate PerformanceEndDate first_end_date

	save "$Data\\people_gap.dta", replace

	// Get hf average return
	use "$DataSource\\ProductPerformance.dta", clear
	sort ProductReference Date
	by ProductReference: egen mean_ret = mean(RateOfReturn)
	by ProductReference: egen mean_asset = mean(EstimatedAssets)
	keep ProductReference mean*
	duplicates drop
	save "$Data\\hf_mean.dta", replace

	
	use "$Data\\people_gap.dta", clear
	merge m:1 ProductReference using "$Data\\hf_mean.dta"
	keep if _merge==3
	drop _merge
	drop first_end_date rolling_date 
	order PersonID ProductReference gap gap2 InceptionDate PerformanceEndDate mean*
	save "$Data\\prelim_full.dta", replace	
	
	drop if gap<0
	sort PersonID ProductReference InceptionDate PerformanceEndDate
	by PersonID: egen max_gap = max(gap)
	keep if max_gap==1
	save "$Data\\prelim_gap_only.dta", replace	
	
	*Check mean return of the relaunched funds (mean return is in percentages points, i.e., 3 = 0.03)
	sum mean_ret if gap==1
	
	*Check mean return of other funds before this guy relaunched
	sum mean_ret if gap==0
		
	
	exit
	
	
