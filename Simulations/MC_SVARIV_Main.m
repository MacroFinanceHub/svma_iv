%% MONTE CARLO STUDY
% Mikkel Plagborg-Moller and Christian Wolf
% This version: 05/21/2018

%% HOUSEKEEPING

clc
clear all
close all

addpath('../Auxiliary Functions')

rng('shuffle')

%% SPECIFY EXPERIMENTS

disp('I am doing a SVAR-IV analysis.')

%----------------------------------------------------------------
% Preparations
%----------------------------------------------------------------

% set benchmark

rho_y_benchmark    = 0.5;
rho_z_benchmark    = 0;
rho_zy_benchmark   = 0;
theta_benchmark    = 0;
sigma_nu_benchmark = 1;
T_benchmark        = 250;

% set selection vectors

n_exp     = 8;

rho_y_all    = rho_y_benchmark * ones(n_exp,1); rho_y_all(2) = 0.9;
rho_z_all    = rho_z_benchmark * ones(n_exp,1); rho_z_all(3) = 0.8;
rho_zy_all   = rho_zy_benchmark * ones(n_exp,1); rho_zy_all(3) = 0.3;
theta_all    = theta_benchmark * ones(n_exp,1); theta_all(4) = 0.5; theta_all(5) = 2;
sigma_nu_all = sigma_nu_benchmark * ones(n_exp,1); sigma_nu_all(6) = 2;
T_all        = T_benchmark * ones(n_exp,1); T_all(7) = 100; T_all(8) = 500;

% placeholders

coverage_all.FVD    = cell(n_exp,1);
coverage_all.IRF    = cell(n_exp,1);

%% SETTINGS

%----------------------------------------------------------------
% Simulation and VAR Estimation
%----------------------------------------------------------------

settings.VAR_poplaglength        = 50; % population VAR lag length
settings.select_VAR_simlaglength = 1;  % estimated VAR: pre-select or choose lag length?

%----------------------------------------------------------------
% Monte Carlo
%----------------------------------------------------------------

settings.n_MC = 5000;

%----------------------------------------------------------------
% Bootstrap
%----------------------------------------------------------------

settings.n_boot          = 1000; % bootstrap draws
settings.signif_level    = 0.1; % significance level
settings.optimopts       = optimoptions('fmincon', 'Display', 'notify'); % options for Stoye CI construction

%----------------------------------------------------------------
% Identified Set Characterization
%----------------------------------------------------------------

settings.VMA_hor        = 50; % maximal horizon in Wold/structural VMA representation
settings.FVD_hor        = [1 4]; % horizons for FVD analysis
settings.FVD_var        = 2;

%----------------------------------------------------------------
% Extra Stuff for Population FVR
%----------------------------------------------------------------

settings.use_KF          = 1; % use Kalman filter for FVR computations?
settings.alpha_ngrid     = 1000; % grid points for lower bound on alpha
settings.bnd_recov       = 1; % naive recoverability-based lower bound on alpha only?
settings.FVR_hor         = settings.FVD_hor; % horizons for FVD analysis
settings.FVR_var         = settings.FVD_var;
settings.CI_for_R2_inv   = 1; % construct CI for R2_inv?
settings.CI_for_R2_recov = 1; % construct CI for R2_recov?
settings.CI_for_FVR      = 1; % construct CI for FVR?
settings.CI_for_FVD      = 1; % construct CI for FVD?

settings.fields          = {'alpha_LB', 'alpha_UB', 'R2_inv_LB', 'R2_inv_UB', 'R2_recov_LB', 'R2_recov_UB', 'FVR_LB', 'FVR_UB', 'FVD_LB'};
settings.fields_param    = {'alpha', 'R2_inv', 'R2_recov', 'FVR'};

%% MAIN LOOP

for i_exp = 1:n_exp
    
disp(['I am doing experiment ' num2str(i_exp)])

%% REST OF SETTINGS

%----------------------------------------------------------------
% Simulation and VAR Estimation
%----------------------------------------------------------------

settings.T                       = T_all(i_exp); % sample size for simulation
settings.VAR_simlaglength        = round(sqrt(settings.T)/2); % estimated VAR lag length (if pre-set)
settings.max_simlaglength        = round(sqrt(settings.T)); % maximal lag length for estimated VAR (when chosen)
settings.penalty                 = @(T) 2/T; % penalty term for lag length selection

%% VAR REPRESENTATION

%----------------------------------------------------------------
% Model Specification
%----------------------------------------------------------------

% raw model parameters

MC_model.rho_y   = rho_y_all(i_exp);
MC_model.Xi_1    = [MC_model.rho_y 0; 0.5 0.5];
MC_model.Theta_0 = chol([1 0.8; 0.8 1],'lower');
MC_model.theta   = theta_all(i_exp);
MC_model.Theta_1 = MC_model.theta * MC_model.Theta_0;

MC_model.Psi_1    = rho_z_all(i_exp);
MC_model.Lambda_1 = rho_zy_all(i_exp) * ones(1,size(MC_model.Theta_0,1));
MC_model.alpha    = 1;
MC_model.sigma_nu = sigma_nu_all(i_exp);

% model size

MC_model.n_y   = size(MC_model.Xi_1,1);
MC_model.n_z   = 1;
MC_model.n_x   = MC_model.n_y + MC_model.n_z;
MC_model.n_eps = size(MC_model.Theta_0,1);
MC_model.n_nu  = 1;
MC_model.n_xi  = MC_model.n_eps + MC_model.n_nu;
MC_model.n_s   = MC_model.n_y + MC_model.n_z + MC_model.n_eps;

% ABCD representation

MC_model.ABCD.A_x = [MC_model.Xi_1 zeros(MC_model.n_y,MC_model.n_z) MC_model.Theta_1; ...
                     MC_model.Lambda_1 MC_model.Psi_1 zeros(MC_model.n_z,MC_model.n_eps); ...
                     zeros(MC_model.n_eps,MC_model.n_s)];
MC_model.ABCD.B_x = [MC_model.Theta_0 zeros(MC_model.n_y,1); ...
                     MC_model.alpha zeros(MC_model.n_z,MC_model.n_eps-1) MC_model.sigma_nu; ...
                     eye(MC_model.n_eps) zeros(MC_model.n_eps,1)];
MC_model.ABCD.C_x = [MC_model.Xi_1 zeros(MC_model.n_y,MC_model.n_z) MC_model.Theta_1; ...
                     MC_model.Lambda_1 MC_model.Psi_1 zeros(MC_model.n_z,MC_model.n_eps)];
MC_model.ABCD.D_x = [MC_model.Theta_0 zeros(MC_model.n_y,1); ...
                     MC_model.alpha zeros(MC_model.n_z,MC_model.n_eps-1) MC_model.sigma_nu];

MC_model.ABCD.A_y = MC_model.ABCD.A_x;
MC_model.ABCD.B_y = MC_model.ABCD.B_x;
MC_model.ABCD.C_y = [MC_model.Xi_1 zeros(MC_model.n_y,MC_model.n_z) MC_model.Theta_1];
MC_model.ABCD.D_y = [MC_model.Theta_0 zeros(MC_model.n_y,1)];

%----------------------------------------------------------------
% Describe Experiment
%----------------------------------------------------------------

disp('The current experiment sets:')
disp(['rho_y = ' num2str(MC_model.rho_y)])
disp(['rho_z = ' num2str(rho_z_all(i_exp))])
disp(['rho_zy = ' num2str(rho_zy_all(i_exp))])
disp(['theta = ' num2str(MC_model.theta)])
disp(['sigma_nu = ' num2str(MC_model.sigma_nu)])
disp(['T = ' num2str(settings.T)])

%----------------------------------------------------------------
% Get Population IRFs + FVDs
%----------------------------------------------------------------

[MC_model.IRF,MC_model.FVD] = pop_analysis(MC_model,settings);
MC_model.IRF = squeeze(MC_model.IRF(settings.FVD_hor,:,1));

%----------------------------------------------------------------
% Get Population SVAR-IV Estimands
%----------------------------------------------------------------

VAR_pop                         = popVAR(MC_model,settings);
[SVARIV_pop.IRF,SVARIV_pop.FVD] = SVARIV_analysis(VAR_pop,MC_model,settings);
yzt_aux                         = get2ndmoments_VAR(VAR_pop,MC_model,settings);
bounds_pop                      = get_IS(yzt_aux,MC_model,settings);
MC_model.FVR                    = bounds_pop.FVR_UB * bounds_pop.alpha_LB^2/MC_model.alpha^2;

%----------------------------------------------------------------
% Placeholders
%----------------------------------------------------------------

IRF_CI_LB = NaN(size(SVARIV_pop.IRF,1),size(SVARIV_pop.IRF,2),settings.n_MC);
IRF_CI_UB = NaN(size(SVARIV_pop.IRF,1),size(SVARIV_pop.IRF,2),settings.n_MC);
FVD_CI_LB = NaN(size(SVARIV_pop.FVD,1),size(SVARIV_pop.FVD,2),settings.n_MC);
FVD_CI_UB = NaN(size(SVARIV_pop.FVD,1),size(SVARIV_pop.FVD,2),settings.n_MC);

%% MONTE CARLO LOOP

parfor i_MC = 1:settings.n_MC
    
% if mod(i_MC,100) == 0
%     disp(i_MC)
% end
    
%----------------------------------------------------------------
% Simulate Data
%----------------------------------------------------------------

data = simulate_data(MC_model,settings);

%----------------------------------------------------------------
% Get VAR Representation
%----------------------------------------------------------------
    
VAR_OLS = estimateVAR_IV(data.y,data.z,settings);  
VAR_sim = VAR_OLS;

%----------------------------------------------------------------
% OLS Point Estimate
%----------------------------------------------------------------

SVARIV_OLS = struct;
[SVARIV_OLS.IRF,SVARIV_OLS.FVD] = SVARIV_analysis(VAR_OLS,MC_model,settings);

%----------------------------------------------------------------
% Bootstrap VAR
%----------------------------------------------------------------

VAR_boot = bootstrapVAR_IV(VAR_OLS,MC_model,data,settings);

%----------------------------------------------------------------
% Pre-Assignment
%----------------------------------------------------------------
 
SVARIV_boot = struct;
SVARIV_boot.IRF = NaN(length(settings.FVD_hor),MC_model.n_y,settings.n_boot);
SVARIV_boot.FVD = NaN(length(settings.FVD_hor),MC_model.n_y,settings.n_boot);

%----------------------------------------------------------------
% Get Identified Sets
%----------------------------------------------------------------

for i_boot = 1:settings.n_boot
    VAR_sim.VAR_coeff_y = VAR_boot.VAR_coeff_y(:,:,i_boot);
    VAR_sim.Sigma_u_y   = VAR_boot.Sigma_u_y(:,:,i_boot);
    VAR_sim.gamma       = VAR_boot.gamma(:,i_boot);
    
    [SVARIV_boot.IRF(:,:,i_boot),SVARIV_boot.FVD(:,:,i_boot)] = SVARIV_analysis(VAR_sim,MC_model,settings);   
end

%----------------------------------------------------------------
% Construct CIs
%----------------------------------------------------------------

[IRF_CI_boot,FVD_CI_boot] = CI_SVARIV_fun(SVARIV_OLS,SVARIV_boot,settings);

%----------------------------------------------------------------
% Collect Results
%----------------------------------------------------------------

% IRF

IRF_CI_LB(:,:,i_MC) = IRF_CI_boot.lower;
IRF_CI_UB(:,:,i_MC) = IRF_CI_boot.upper;

% FVD

FVD_CI_LB(:,:,i_MC) = max(0,FVD_CI_boot.lower);
FVD_CI_UB(:,:,i_MC) = min(1,FVD_CI_boot.upper);

end

clear IRF_CI_boot FVD_CI_boot i_boot i_MC VAR_boot VAR_OLS VAR_sim SVARIV_OLS SVARIV_boot

%% RESULTS

%----------------------------------------------------------------
% FVR
%----------------------------------------------------------------

% focus on one variable

FVD_CI_LB = squeeze(permute(FVD_CI_LB(:,settings.FVD_var,:),[3 1 2]));
FVD_CI_UB = squeeze(permute(FVD_CI_UB(:,settings.FVD_var,:),[3 1 2]));

% report coverage

for hor_ind = 1:length(settings.FVD_hor)
    
    hor = settings.FVD_hor(hor_ind);
    coverage.FVD{hor_ind} = (FVD_CI_LB(:,hor_ind) <= MC_model.FVR(hor_ind,settings.FVD_var) & FVD_CI_UB(:,hor_ind) >= MC_model.FVR(hor_ind,settings.FVD_var));
    disp(['The fraction of confidence intervals for FVR at horizon ' num2str(hor) ' covering the truth is ' num2str(sum(coverage.FVD{hor_ind})/settings.n_MC)])
    
end

coverage_all.FVD{i_exp} = coverage.FVD;

%----------------------------------------------------------------
% IRF
%----------------------------------------------------------------

% focus on one variable

IRF_CI_LB = squeeze(permute(IRF_CI_LB(:,settings.FVD_var,:),[3 1 2]));
IRF_CI_UB = squeeze(permute(IRF_CI_UB(:,settings.FVD_var,:),[3 1 2]));

% report coverage

for hor_ind = 1:length(settings.FVD_hor)
    
    hor = settings.FVD_hor(hor_ind);
    coverage.IRF{hor_ind} = (IRF_CI_LB(:,hor_ind) <= MC_model.IRF(hor_ind,settings.FVD_var) & IRF_CI_UB(:,hor_ind) >= MC_model.IRF(hor_ind,settings.FVD_var));
    disp(['The fraction of confidence intervals for IRF at horizon ' num2str(hor) ' covering the truth is ' num2str(sum(coverage.IRF{hor_ind})/settings.n_MC)])
    
end

coverage_all.IRF{i_exp} = coverage.IRF;

end