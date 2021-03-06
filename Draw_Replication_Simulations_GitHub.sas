**********************************************************************
**********************************************************************

Fisheries intercept survey simulation code for a constrained draw 
replication approach to select site-day primary sampling units

Program written by J Foster (annotated by KJ Papacostas)

This program accompanies the following article: 
Papacostas and Foster. Fisheries Research 2020
Title: A replication approach to controlled selection for catch 
sampling intercept surveys

This program is divided into 6 sections:  the first is a set of
macro variable parameters used by subsequent sections of the program.
Section 2 is a macro entitled 'main' which calls the series of 4 macros
comprising Sections 3,4,5 and 6. A summary of what each individual 
macro does can be found below in Section 2, and then each macro is also
annotated in more detail in Sections 3-6 below.

5 sets of output SAS datasets are generated by this program: 4 sets of 
datasets are generated by Section 4 and relate to the drawing of samples 
at different replication levels (see Section 4 annotation). The final 
set of datasets contain all the catch estimates that are generated by
Section 5 (see Section 5 annotation).
**********************************************************************
**********************************************************************;





**********************************************************************
**********************************************************************

SECTION 1:  INPUT PARAMETERS

This section sets the macro variables to be used in the subsequent 
sections of this program:

nsites = the number of fishing access sites in the simulated survey
ndays = the number of days to be sampled
site_seed = seed to generate a random set of numbers for sites each 
			time the program is run
npsus = primary stage units (site-days)
pop_catch = true catch (i.e.total catch/sum of catch-per-unit)
catch_seed = seed to generate a random set of numbers for catch each 
			 time the program is run
rho = parameter used to generate catch-per-unit distribution
	  scenarios correlated with size measure
nsamp = sample size
sum_day = the number of sites for the sites-per-day constraint imposed on the sample draw
samp_frac = sampling fraction
day_frac = constraint fraction
reps = desired number of replicated samples to generate
draw_seed = seed to draw a random set of sampling units for the sample draw 
			each time the program is run
sim_reps = number of iterations for the constrained simulation

**********************************************************************
**********************************************************************;

%let out_path=ENTER_DESIRED_FILEPATH_FOR_OUTPUT_DATASETS;

libname out "&out_path.";
%let nsites=30;
%let ndays=30;
%let site_seed=100;
%let npsus=%sysevalf(&nsites.*&ndays.);

%let pop_catch=100000;
%let catch_seed=300;
%let rho=0.95;

%let nsamp=30;
%let sum_day=2;
%let samp_frac=%sysevalf(&nsamp./&npsus.);
%let day_frac=%sysevalf(&sum_day./&nsites.);

%put samp_frac=&samp_frac.;
%put day_frac=&day_frac.;

%let reps=500 1000 2000 5000 10000 20000 50000;
%let draw_seed=0;

%let sim_reps=1000;





**********************************************************************
**********************************************************************

SECTION 2:  RUN MACROS

This section runs the following series of macros: 

make_frame: generates the sample frame for use in the simulation
reps_loop:  	draws sets of replicated samples using constrained and
			unconstrained draw replication processes
ereps_loop:	loops through a macro entitled 'estimation' for each set 
			of replicated samples.  The estimation macro estimates total 
			catch and variance for each catch-per-unit distribution 
			scenario (these were divided into two macros rather than being
			one larger one purely to reduce the memory required for the
			individual sets of iterative computations).
eval_surv_reps: calculates bias in estimates relative to the true catch, 
				and evaluates missing frame units from the survivor 
				subsets of replicated samples.

**********************************************************************
**********************************************************************;

%macro main;

	%make_frame;

	%reps_loop;

	%ereps_loop;

	%eval_surv_reps;

%mend main;

**********************************************************************
**********************************************************************

SECTION 3: CREATE THE SAMPLE FRAME

The code below creates the sample frame/simulated population using the 
macro variables set above in Section 1.  Each frame unit is assigned a 
size measure to represent different levels of fishing pressure and 
3 different catch-per unit distribution scenarios, meant to represent 
different scenarios for the distribution of catch in relation to 
the level of site-specific fishing activity:
1) catch_poi = standard Poisson distribution
2) catch_pcorr = Poisson distribution positively correlated with size 
	measure
3) catch_ncorr = Poisson negatively correlated with size measure

**********************************************************************
**********************************************************************;

%Macro make_frame;

data sites;
	do site_id=1 to &nsites.;
		rndp=ranuni(&site_seed.);
		if rndp<=0.05 then size=20;
		if 0.05<rndp<=0.40 then size=10;
		if 0.40<rndp<=1 then size=5;
		output;
	end;
run;

proc sql noprint;
	create table fullframe as
	select *
	from sites,calendar
	;
	create table fullframe as
	select *,count(size) as size_cnt
	from fullframe
	group by size;
quit;

proc sql noprint;
	create table fullframe as
	select *,mean(size) as size_mean,
			std(size) as size_std
	from fullframe
	;
quit;

data fullframe;
	set fullframe;
	psu_id=compress(site_id||"."||day);
	catch_poi = ranpoi(&catch_seed.,(&pop_catch./&npsus.));
	catch_pcorr=round((&pop_catch./&npsus.)+&rho.*sqrt(&pop_catch./&npsus.)*((size-size_mean)/size_std)+
				sqrt((&pop_catch./&npsus.)-(&pop_catch./&npsus.)*&rho.**2)*
				((catch_poi-(&pop_catch./&npsus.))/sqrt(&pop_catch./&npsus.)),1);
	catch_ncorr=round((&pop_catch./&npsus.)-&rho.*sqrt(&pop_catch./&npsus.)*((size-size_mean)/size_std)+
				sqrt((&pop_catch./&npsus.)-(&pop_catch./&npsus.)*&rho.**2)*
				((catch_poi-(&pop_catch./&npsus.))/sqrt(&pop_catch./&npsus.)),1);
run;

proc sql;
	create table fullframe as
	select *,sum(catch_poi) as sum_poi
		,sum(catch_pcorr) as sum_pcorr
		,sum(catch_ncorr) as sum_ncorr
	from fullframe
	;
quit;

data fullframe;
	set fullframe;
	catch_poi_cal = catch_poi * (&pop_catch./sum_poi);
	catch_pcorr_cal = catch_pcorr * (&pop_catch./sum_pcorr);
	catch_ncorr_cal = catch_ncorr * (&pop_catch./sum_ncorr);
run;

proc sql;
	select sum(catch_poi_cal) as sum_poi_cal
		,sum(catch_pcorr_cal) as sum_pcorr_cal
		,sum(catch_ncorr_cal) as sum_ncorr_cal
	from fullframe
	;
quit;

%Mend make_frame;

**********************************************************************
**********************************************************************

SECTION 4:  SELECT SAMPLES

This section draws the sets of replicated samples (set by the macro 
variable "reps" in Section 1), filters them through constraints, and 
selects a final sample as the official draw for the survey.  The 
process is then repeated as many times as is specified by sim_reps 
(macro variable also defined in Section 1).

This section also draws the sets of replicated samples in an 
unconstrained manner (i.e. just draws the sets of replicated samples 
set by reps without applying any filters).

Finally, this section further generates the following sets of SAS 
datasets (one set for each replication level (e.g. inc_prob_sum_500, 
inc_prob_sum_1000....inc_prob_sum_50000)) as output:

1) inc_prob_sum_&rep. --> lists the number of surviving replicated 
samples, and the sum of the inclusion probabilities in the constrained 
simulation at each replication level - this is simply used as a 
diagnostic dataset to ensure the draw process was successful.

2) draw_sim_&rep. --> lists full sets of replicated draws prior to
applying any constraints at each replication level.

3) psu_miss_sim_&rep. --> lists the set of primary stage units 
missing from the surviving set of replicated samples in the 
constrained simulation at each replication level.

4) draw_cntrl_&rep. --> lists the survivor sets of replicated
samples after filtering through constraints for each replication level.

**********************************************************************
**********************************************************************;

%Macro rep_loop;
	%put start time = %sysfunc(time(),time.8);
		%put replicates level = &rep.;
		data draw_sim_full psu_miss_sim_full draw_cntrl_full;
			set _null_;
		run;
		%do sim_loop = 1 %to 1;
			%put sim loop = &sim_loop.;
		proc surveyselect data=fullframe method=pps
			sampsize=&nsamp. reps=&rep. outseed outsize stats
			out=draw;
			size size;
		run;

		proc sql;
			create table day_cnt as
				select replicate,day,count(day) as day_cnt
				from draw
				group by replicate,day
			;
		quit;
		proc sql;
			create table day_cnt2 as
				select replicate,max(day_cnt) as max_day_cnt
				from day_cnt
				group by replicate
			;
		quit;
		proc sql;
			create table pass_sum_day2 as
				select *,count(distinct replicate) as surv_reps
				from draw
				where replicate in
					(select replicate
					 from day_cnt2
					 where max_day_cnt <= &sum_day.
					 )
			;
		quit;
		proc sql;
			create table pass_sum_day3 as
				select *,count(psu_id) as psu_id_cnt
				from pass_sum_day2
				group by psu_id
			;
		quit;
		data pass_sum_day;
			set pass_sum_day3;
			tot_reps=&rep.;
			obs_inc_prob=psu_id_cnt/surv_reps;
			obs_sampling_weight=1/obs_inc_prob;
		run;
		proc sort data=fullframe;
			by psu_id;
		run;
		proc sort data=pass_sum_day out=pass_sum_day_nodup
			nodupkey;
			by psu_id;
		run;
		proc sql;
			create table out.inc_prob_sum_&rep. as
			select tot_reps,surv_reps,sum(obs_inc_prob) as inc_prob_sum,
				count(psu_id) as psu_count
			from pass_sum_day_nodup
			group by tot_reps,surv_reps
			;
		quit;
		data psu_miss2;
			merge fullframe(in=f) pass_sum_day_nodup(in=p keep=psu_id);
			by psu_id;
			if f and p then psu_incl=1;
			if f and not p then psu_incl=0;
			if f;
			sim_round=&sim_loop.;
		run;
		proc sql;
			create table psu_miss as
			select *,mean(psu_incl) as prop_psu_incl
			from psu_miss2
			group by sim_round;
		quit;
		data psu_miss_sim_full;
			set psu_miss_sim_full 
				psu_miss(where=(psu_incl=0));
		run;
		proc sort data=pass_sum_day out=replicates(keep=replicate)
			nodupkey;
			by replicate;
		run;
		proc sort data=draw out=replicates_cntrl(keep=replicate)
			nodupkey;
			by replicate;
		run;
		proc surveyselect data=replicates(rename=(replicate=orig_replicate)) method=srs sampsize=1 reps=&sim_reps. 
			outseed outsize stats out=rep_drw;
		run;
		proc surveyselect data=replicates_cntrl(rename=(replicate=orig_replicate)) method=srs sampsize=1 reps=&sim_reps. 
			outseed outsize stats out=rep_drw_cntrl;
		run;
		data rep_drw;
			set rep_drw(rename=(replicate=sim_replicate));
			replicate=orig_replicate;
			drop orig_replicate;
		run;
		data rep_drw_cntrl;
			set rep_drw_cntrl(rename=(replicate=sim_replicate));
			replicate=orig_replicate;
			drop orig_replicate;
		run;
		
			proc sql;
			%do s_i=1 %to &sim_reps.;
				create table draw_tmp_&s_i. as
				select *,&s_i. as sim_round
				from pass_sum_day
				where replicate in
					(select replicate from rep_drw
					where sim_replicate=&s_i.)
				;
				create table draw_cntrl_&s_i. as
				select *,&s_i. as sim_round 
				from draw
				where replicate in
					(select replicate from rep_drw_cntrl
					where sim_replicate=&s_i.)
				;
			%end;
			quit;
		data draw_sim_full;
			set
				%do s_i = 1 %to &sim_reps.;
					draw_tmp_&s_i.
				%end;
			;
		run;
		data draw_cntrl_full;
			set
				%do s_i = 1 %to &sim_reps.;
					draw_cntrl_&s_i.
				%end;
			;
		run;

		data out.draw_sim_&rep.;
			set draw_sim_full;
		run;
		data out.draw_cntrl_&rep.;
			set draw_cntrl_full;
		run;
		data out.psu_miss_sim_&rep.;
			set psu_miss_sim_full;
		run;

	%end;
	%put stop time = %sysfunc(time(),time.8);
%Mend rep_loop;

%Macro reps_loop;
	
	%let r_i=1;
	%do %while(%scan(&reps.,&r_i.,' ')^= );
		%let rep=%scan(&reps.,&r_i.,' ');
		%put &r_i. &rep.;
		option nonotes;
		%rep_loop;
		option notes;
		%let r_i=%eval(&r_i.+1);
	%end;
	
%Mend reps_loop;

**********************************************************************
**********************************************************************

SECTION 5: ESTIMATION

This section produces catch and variance estimates for the simulated 
surveys using a standard weighted total estimator.

Note that the results for draw = 1 and draw = 4 are the results presented 
in the paper.  The other methods included here (2, 3, 5 and 6) are just 
different post-stratification adjustments for comparison purposes 
(the post-stratification adjustments are applied to the 
count of the sampling units in the frame so that the sum of the weights 
exactly match the count of units in the frame).

This macro generates the following set of SAS datasets as outputs:
1) catchests_&erep. --> estimates organized by replication level for 
both the constrained and unconstrained simulations.

**********************************************************************
**********************************************************************;
%Macro estimation;
	proc sort data=out.draw_cntrl_&erep.;
		by sim_round;
	run;
	ods graphics off;
	proc surveymeans data=out.draw_cntrl_&erep. sum sumwgt
		plots=(none);
		by sim_round;
		weight samplingweight;
		var catch_poi_cal catch_pcorr_cal catch_ncorr_cal;
		ods output statistics=cntrl_catch;
	run;
	proc sort data=out.draw_sim_&erep.;
		by sim_round;
	run;
	proc sql;
		create table draw_sim_ps1 as
		select *,sum(obs_sampling_weight) as sum_weight
		from out.draw_sim_&erep.
		group by sim_round
		;
		create table draw_sim_ps2 as
		select *,sum(obs_sampling_weight) as sum_weight
		from out.draw_sim_&erep.
		group by sim_round,size_cnt
		;
		select max(surv_reps) into: surv_reps
		from out.draw_sim_&erep.
		;
		create table draw_cntrl_ps1 as
		select *,sum(samplingweight) as sum_weight
		from out.draw_cntrl_&erep.
		group by sim_round
		;
		create table draw_cntrl_ps2 as
		select *,sum(samplingweight) as sum_weight
		from out.draw_cntrl_&erep.
		group by sim_round,size_cnt
		;
	quit;
	%put &surv_reps.;
	data draw_sim_ps1;
		set draw_sim_ps1;
		weight_ps = obs_sampling_weight * ((&nsites.*&ndays.)/sum_weight);
	run;
	data draw_sim_ps2;
		set draw_sim_ps2;
		weight_ps = obs_sampling_weight * ((size_cnt)/sum_weight);
	run;
	data draw_cntrl_ps1;
		set draw_cntrl_ps1;
		weight_ps = samplingweight * ((&nsites.*&ndays.)/sum_weight);
	run;
	data draw_cntrl_ps2;
		set draw_cntrl_ps2;
		weight_ps = samplingweight * ((size_cnt)/sum_weight);
	run;
	proc surveymeans data=out.draw_sim_&erep. sum sumwgt
		plots=(none);
		by sim_round;
		weight obs_sampling_weight;
		var catch_poi_cal catch_pcorr_cal catch_ncorr_cal;
		ods output statistics=sim_catch;
	run;
	ods graphics off;
	proc surveymeans data=draw_sim_ps1 sum sumwgt
		plots=(none);
		by sim_round;
		weight weight_ps;
		var catch_poi_cal catch_pcorr_cal catch_ncorr_cal;
		ods output statistics=sim_catch_ps1;
	run;
	proc surveymeans data=draw_sim_ps2 sum sumwgt
		plots=(none);
		by sim_round;
		weight weight_ps;
		var catch_poi_cal catch_pcorr_cal catch_ncorr_cal;
		ods output statistics=sim_catch_ps2;
	run;
	proc surveymeans data=draw_cntrl_ps1 sum sumwgt
		plots=(none);
		by sim_round;
		weight weight_ps;
		var catch_poi_cal catch_pcorr_cal catch_ncorr_cal;
		ods output statistics=cntrl_catch_ps1;
	run;
	proc surveymeans data=draw_cntrl_ps2 sum sumwgt
		plots=(none);
		by sim_round;
		weight weight_ps;
		var catch_poi_cal catch_pcorr_cal catch_ncorr_cal;
		ods output statistics=cntrl_catch_ps2;
	run;
	data both;
		set cntrl_catch(in=cc) sim_catch(in=s) cntrl_catch_ps1(in=c1)
			cntrl_catch_ps2(in=c2)
			sim_catch_ps1(in=p1)
			sim_catch_ps2(in=p2)
		;
		if cc then  draw="1.Unconstrained PPS    ";
		if s then  draw= "4.Constrained PPS      ";
		if c1 then draw= "2.Unconstrained PPS PS1";
		if c2 then draw= "3.Unconstrained PPS PS2";
		if p1 then  draw="5.Constrained PPS PS1   ";
		if p2 then  draw="6.Constrained PPS PS2   ";
	run;
	data out.catchests_&erep.;
		set both;
		init_reps=&erep.;
		surv_reps=&surv_reps.;
	run;

	proc sort data=both;
		by varname draw;
	run;

%Mend estimation;

%Macro ereps_loop;
	
	%let r_i=1;
	%do %while(%scan(&reps.,&r_i.,' ')^= );
		%let erep=%scan(&reps.,&r_i.,' ');
		%put &r_i. &erep.;
/*Comment out the option nonotes line below for debugging as needed.*/
		option nonotes;
		%estimation;
		option notes;
		%let r_i=%eval(&r_i.+1);
	%end;
	
%Mend ereps_loop;

**********************************************************************
**********************************************************************

SECTION 6: EVALUATING RESULTS

This section of the program evaluates the results of the simulations, 
including the frame units missing from the replicated samples in the 
constrained simulation, and the bias in the catch estimates relative 
to the true catch (pop_catch in Section 1).

Note that rbias2 is calculated as ((estimate- true)/true) and is the 
relative bias estimation used in the paper.  Rbias was a method used 
prior to peer-review and is estimated as ((estimate-true)/estimate).  
Both were kept here simply for comparison purposes.

**********************************************************************
**********************************************************************;

%Macro eval_surv_reps;

	%let greps=500 1000 2000 5000 10000 20000 50000;
	%let g_i=1;
	data surv_prop wgt_diff catchests;
		set _null_;
	run;
	%do %while(%scan(&greps.,&g_i.)^= );
		%let g_rep=%scan(&greps.,&g_i.);
	proc sql;
		%if &g_rep.<10000 %then %do;
		create table surv_&g_rep. as
		select distinct a.prop_psu_incl, &g_rep. as init_reps, b.surv_reps
		from out.psu_miss_sim_&g_rep. as a, out.draw_sim_&g_rep. as b;
		%end;
		%if &g_rep.>=10000 %then %do;
		create table surv_&g_rep. as
		select distinct 1 as prop_psu_incl, &g_rep. as init_reps, b.surv_reps
		from out.draw_sim_&g_rep. as b;
		%end;
	quit;
	data surv_prop;
		set surv_prop surv_&g_rep.;
	run;
	
	proc sql;
		create table size_&g_rep. as
		select distinct size,samplingweight
		from out.draw_sim_&g_rep.
		order by size;
	quit;
	data miss_&g_rep.;
		set out.psu_miss_sim_&g_rep.;
		keep psu_id size;
	run;
	proc sort data=miss_&g_rep. nodupkey;
		by psu_id;
	run;
	proc sort data=miss_&g_rep.;
		by size;
	run;
	data miss_&g_rep.;
		merge miss_&g_rep.(in=m) size_&g_rep.;
		by size;
	run;
	data miss_&g_rep.;
		set miss_&g_rep.;
		obs_sampling_weight=0;
	run;
	proc sql;
		create table diff_&g_rep. as
		select distinct &g_rep. as init_reps, surv_reps, psu_id, 
			samplingweight, obs_sampling_weight
		from out.draw_sim_&g_rep.;
	quit;
	data diff_&g_rep.;
		set diff_&g_rep. miss_&g_rep.;
		diff_s_o=abs(samplingweight-obs_sampling_weight);
	run;
	proc sql;
		create table diff_&g_rep. as
		select *,max(surv_reps) as surv_reps2,
			max(init_reps) as init_reps2
		from diff_&g_rep.
		;
		create table diff_&g_rep. as
		select init_reps2, surv_reps2, sum(diff_s_o) as abs_diff
		from diff_&g_rep.
		group by init_reps2, surv_reps2;
	quit;
	data wgt_diff;
		set wgt_diff diff_&g_rep.;
	run;
	data catchests;
		set catchests 
			out.catchests_&g_rep.(where=(
				substr(draw,1,1) in ("1" "2" "3" "4" "5" "6")
				));
		cv=stddev/sum;
		varref=0;
		if substr(draw,1,1) in ("1") then varref=1;
		if draw="5.Contrained PPS PS1   " then draw="5.Constrained PPS PS1   ";
		if draw="6.Contrained PPS PS2   " then draw="6.Constrained PPS PS2   ";
		varsum=stddev**2;
	run;
		%let g_i=%eval(&g_i.+1);
	%end;
	data surv_prop;
		set surv_prop;
		prop_psu_miss=1-prop_psu_incl;
	run;
	
	proc sql;
		create table catchests as
		select *,mean(varref*varsum) as varsum_pre 
		from catchests
		group draw,varname
		;
		create table catchests as
		select *,max(varsum_pre) as varsum_ref
		from catchests
		group varname
		;
	quit;
	proc sql;
		create table catchests as
		select *,mean(sum) as sum_gmean 
			,mean(sumwgt) as sumwgt_gmean
			,mean(varsum) as varsum_gmean
		from catchests
		group by draw,varname,surv_reps
		;
	quit;
	data catchests;
		set catchests;
		sum_bias=sum_gmean-&pop_catch.;
		sum_rbias=sum_bias/sum_gmean;
		sum_rbias2=sum_bias/&pop_catch.;
		sumwgt_bias=sumwgt_gmean-%eval(&nsites.*&ndays.);
		sumwgt_rbias=sumwgt_bias/sumwgt_gmean;
		sumwgt_rbias2=sumwgt_bias/%eval(&nsites.*&ndays.);
	run;
	data catchests;
		set catchests;
		if substr(draw,1,1) in ("1" "2" "3") then replicates=init_reps;
		if substr(draw,1,1) in ("4" "5" "6") then replicates=surv_reps;
		if varname="catch_ncorr_cal" then varname='ncor';
		if varname="catch_pcorr_cal" then varname='pcor';
		if varname="catch_poi_cal" then varname='poi';
	run;
	proc sort data=catchests;
		by draw;
	run;

	data catchests;
		set catchests;
		if draw="1.Unconstrained PPS" then do;
			if init_reps=50000 then output;
		end;
		if draw^="1.Unconstrained PPS" then output; 
	run;

    proc format;
        value $draw "1.Unconstrained PPS" = "Unconstrained" "4.Constrained PPS" = "Constrained"; 
    run;

	proc sql;
		create table bias as
		select distinct draw,varname,surv_reps,replicates,
			sum_bias,sum_rbias,sum_rbias2,sumwgt_bias,sumwgt_rbias,sumwgt_rbias2
		from catchests;
	quit;
	proc sort data=surv_prop;
		by surv_reps;
	run;
	proc sort data=bias;
		by surv_reps;
	run;
	data bias2;
		merge bias(in=b) surv_prop(keep=surv_reps prop_psu_miss);
		by surv_reps;
	run;
	data bias2;
		set bias2;
		if substr(draw,1,1)="4";
		ref_prop_miss = -1*sum_rbias;
		reference = -1*sum_rbias2;
	run;

%Mend eval_surv_reps;

%main;
