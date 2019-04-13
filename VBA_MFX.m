function [posterior_sub,out_sub,posterior_group,out_group] = VBA_MFX(y,u,f_fname,g_fname,dim,options)
% VB treatment of mixed-effects analysis
% function [posterior,out] = VBA_MFX(y,u,f_fname,g_fname,dim,options)
% This function approaches model inversion from an empirical Bayes
% perspective, whereby within-subject priors are iteratively refined and
% matched to the inferred parent population distribution.
%  Note: all subjects must use the same model
% IN:
%   - y: nsx1 cell array of observations, where ns is the number of
%   subjects in the group
%   - u:  nsx1 cell array of inputs
%   - f_fname/g_fname: evolution/observation function handles
%   - dim: structure containing the model dimensions.
%   - options: nsx1 cell array of options structure. Note: if specified
%   here, the priors on observation and evolution parameters (as well as
%   initial conditions) are useless, since they are replaced by empirical
%   Bayes priors. Priors on precision hyperparameters however, are not
%   treated as random effects drawn from a parent population distribution.
%   In turn, MFX analysis does not update their moments using group-level
%   information...
%   - priors_group: structure containing the prior sufficient statistics on
%   the moments of the parent population distributions (for observation and
%   evolution parameters, as well as for initial conditions, if
%   applicable). See p_group subfields below.
%   - options_group: Structure containing options for MFX. Fields:
%     .TolFun - Minimum change in the free energy, default is 2e-2
%     .MaxIter - Maximum number of iterations, default is 16
%     .DisplayWin - Do we want a graphical output?
%     .verbose - Do we want verbose text output?
%
% OUT:
%   - p_sub/o_sub: nsx1 cell arrays containng the VBA outputs of the
%   within-subject model inversions.
%   - p_group: structure containing the sufficient statistics of the
%   posterior over the moments of the parent population distribution. Its
%   subfields are:
%       .muPhi/SigmaPhi: VB sufficient statistics (first 2 moments) of the
%       Gaussian posterior pdf over the population mean of observation
%       parameters.
%       .muTheta/SigmaTheta: [id] for evolution parameters.
%       .muX0/SigmaX0: [id] for initial conditions.
%       .a_vPhi/b_vPhi: VB sufficient statistics (scale and shape
%       parameters) of the Gamma posterior pdf over the population
%       precision of observation parameters. NB: a_vPhi and b_vPhi have the
%       same dimension than muPhi!
%       .a_vTheta/b_vTheta: [id] for evolution parameters.
%       .a_vX0/b_vX0: [id] for initial conditions.
%   - o_group: output structure of the VBA_MFX approach. In particular, it
%   contains the following subfields:
%       .F: a vector of free energies (across VB iterations). Its last
%       entry (F(end)) provides the free energy lower bound to the MFX
%       model.
%       .it: the final number of VB iterations
%       .date: date vector for track keeping
%       .initVBA: a structure containing the VBA outputs of the
%       within-subject model inversions, without MFX-type priors
%       (initialization).


%% Check parameters
% =========================================================================

if ~ exist('options','var')
    options = struct ();
end
options = VBA_check_struct (options, VBA_defaultOptions ());

%% Shortcuts
% =========================================================================
% Number of subjects
nS = length(y); 

% expand inputs to an array if necessary
if isnumeric (u)
    temp = cell (1, nS);
    temp(:) = {u};
    u = temp;
end


%% Check priors
% =========================================================================
% Default priors are used if priors are not explicitly provided through the
% priors_group structure. This means Gaussian(0,1) priors for the
% population mean of observation/evolution parameters and initial
% conditions, and Gamma(1,1) for the corresponding population precisions.

if ~ isfield(options,'priors')
    options.priors = struct ();
end
priors_group = VBA_check_struct (options.priors, VBA_defaultMFXPriors (dim));

%% Initialization
% =========================================================================
% Here, we simply initialize the posterior on the population's mean and
% precision over observation/evolution parameters and initial conditions
% using their prior.

VBA_disp ('VBA treatment of MFX analysis: initialization...', options)

for i=1:nS
    %if dim.n_phi > 0
        iV_phi = VBA_inv(priors_group.SigmaPhi);
        ind.phi_ffx = find(isFixedEffect(priors_group.a_vPhi,priors_group.b_vPhi));
        ind.phi_rfx = find(~ isFixedEffect(priors_group.a_vPhi,priors_group.b_vPhi));
        ind.phi_in = find(diag(priors_group.SigmaPhi)~=0);
    %end
    %if dim.n_theta > 0
        iV_theta = VBA_inv(priors_group.SigmaTheta);
        ind.theta_ffx = find(isFixedEffect(priors_group.a_vTheta,priors_group.b_vTheta));
        ind.theta_rfx = find(~ isFixedEffect(priors_group.a_vPhi,priors_group.b_vPhi));
        ind.theta_in = find(diag(priors_group.SigmaTheta)~=0);
    %end
    %if dim.n >0
        iV_x0 = VBA_inv(priors_group.SigmaX0);
        ind.x0_ffx = find(isFixedEffect(priors_group.a_vX0,priors_group.b_vX0));
        ind.x0_rfx = find(~ isFixedEffect(priors_group.a_vX0,priors_group.b_vX0));
        ind.x0_in = find(diag(priors_group.SigmaX0)~=0);
    %end
end


%%
options.dim = dim;
options.dim.ns = nS;

out_group.ind = ind;

%%
% 2- evaluate within-subject free energies under the prior

% save here to acces subject specific trial numbers later
if numel(dim.n_t) == 1
    n_t = repmat(dim.n_t,1,nS);
else
    n_t = dim.n_t;
end

for i=1:nS
    
    options_subject{i}.priors = getSubjectPriors(priors_group, ind, nS);

    % VBA model inversion
    options_subject{i}.DisplayWin = 0;
    options_subject{i}.verbose = 0;
    options_subject{i}.MaxIter = 0;
    
    dim.n_t = n_t(i);  % subject number of trials
    
    in{i} = [];
    
    [posterior_sub{i},out_sub{i}] = VBA_NLStateSpaceModel(y{i},u{i},f_fname,g_fname,dim,options_subject{i});
    
    % store options for future inversions
    options_subject{i} = out_sub{i}.options;
    options_subject{i}.MaxIter = 32;

end

posterior_group = priors_group;
out_group.options = options;

F(1) = MFX_F(posterior_sub,out_sub,posterior_group,priors_group,dim,ind);

out_group.F = F;
out_group.it = 0;
out_group.ind = ind;
out_group.options = options;

[out_group.options] = VBA_displayMFX(posterior_sub,out_sub,posterior_group,out_group,0,'off');



% 3- VB: iterate until convergence...
% We now update the within-subject effects as well as respective population
% moments according to the mean-field VB scheme. This effectively
% iteratively replaces the priors over within-subject effects by the VB
% estimate of the group mean and precision. The free energy of the ensuing
% MFX procedure is computed for tracking algorithmic convergence.
stop = 0;
it = 1;
fprintf(1,['Main VB inversion...'])
while ~stop
    
    % perform within-subject model inversions
    for i=1:nS
        
        
        try
            set(out_group.options.display.ho,'string',['VB iteration #',num2str(it),': within-subject model inversions (',num2str(floor(100*(i-1)/nS)),'%)'])
        end
        
        % re-define within-subject priors
        options_subject{i}.priors = updateSubjectPriors(options_subject{i}.priors, posterior_group, ind);

        
        % bypass VBA initialization

        % VBA model inversion
        [posterior_sub{i},out_sub{i}] = VBA_NLStateSpaceModel(y{i},u{i},f_fname,g_fname,dim,options_subject{i},in{i});
        
        in{i}.posterior = posterior_sub{i};
        in{i}.out = out_sub{i};
        in{i}.out.options = options_subject{i};
        
        % store sufficient statistics
        if dim.n_phi > 0
            mphi(:,i) = posterior_sub{i}.muPhi;
            Vphi{i} = posterior_sub{i}.SigmaPhi;
        end
        if dim.n_theta > 0
            mtheta(:,i) = posterior_sub{i}.muTheta;
            Vtheta{i} = posterior_sub{i}.SigmaTheta;
        end
        if dim.n >0
            mx0(:,i) = posterior_sub{i}.muX0;
            Vx0{i} = posterior_sub{i}.SigmaX0;
        end
        
    end
    
    try
        set(out_group.options.display.ho,'string',['MFX: updating moments of parent distribution...'])
    end
    
    % update moments of the parent population distribution
    if dim.n_phi > 0
        [posterior_group.muPhi,posterior_group.SigmaPhi,posterior_group.a_vPhi,posterior_group.b_vPhi] = ...
            MFX_VBupdate(...
            priors_group.muPhi,...
            iV_phi,...
            mphi,...
            Vphi,...
            posterior_group.a_vPhi,...
            posterior_group.b_vPhi,...
            priors_group.a_vPhi,...
            priors_group.b_vPhi,...
            ind.phi_ffx,...
            ind.phi_in);
    end
    if dim.n_theta > 0
        [posterior_group.muTheta,posterior_group.SigmaTheta,posterior_group.a_vTheta,posterior_group.b_vTheta] = ...
            MFX_VBupdate(...
            priors_group.muTheta,...
            iV_theta,...
            mtheta,...
            Vtheta,...
            posterior_group.a_vTheta,...
            posterior_group.b_vTheta,...
            priors_group.a_vTheta,...
            priors_group.b_vTheta,...
            ind.theta_ffx,...
            ind.theta_in);
    end
    if dim.n >0
        [posterior_group.muX0,posterior_group.SigmaX0,posterior_group.a_vX0,posterior_group.b_vX0] = ...
            MFX_VBupdate(...
            priors_group.muX0,...
            iV_x0,...
            mx0,...
            Vx0,...
            posterior_group.a_vX0,...
            posterior_group.b_vX0,...
            priors_group.a_vX0,...
            priors_group.b_vX0,...
            ind.x0_ffx,...
            ind.x0_in);
    end
    
    F(it+1) = MFX_F(posterior_sub,out_sub,posterior_group,priors_group,dim,ind);
    
    out_group.F = F;
    out_group.it = it;
    
    if it == 1
        % store initial within-subject VBA model inversion
        out_group.initVBA.p_sub = posterior_sub;
        out_group.initVBA.o_sub = out_sub;
        [out_group.options] = VBA_displayMFX(posterior_sub,out_sub,posterior_group,out_group,0,'off');
    else
        [out_group.options] = VBA_displayMFX(posterior_sub,out_sub,posterior_group,out_group);
    end
    
    dF = F(it+1) - F(it);
    if abs(dF) <= options.TolFun || it >= options.MaxIter
        stop = 1;
    end
    it = it +1;
    
end
fprintf([' done.','\n'])
out_group.date = clock;
out_group.options.sources = out_sub{1}.options.sources;
for i=1:nS
    out_group.within_fit.F(i) = out_sub{i}.F(end);
    out_group.within_fit.R2(i,:) = out_sub{i}.fit.R2;
    out_group.within_fit.LLH0(i) = VBA_LMEH0(out_sub{i}.y,out_sub{i}.options);
    [tmp,out_sub{i}] = VBA_getDiagnostics(posterior_sub{i},out_sub{i});
end
[out_group.options] = VBA_displayMFX(posterior_sub,out_sub,posterior_group,out_group);
try
    if floor(out_group.dt./60) == 0
        timeString = [num2str(floor(out_group.dt)),' sec'];
    else
        timeString = [num2str(floor(out_group.dt./60)),' min'];
    end
    set(out_group.options.display.ho,'string',['VB treatment of MFX analysis complete (took ~',timeString,').'])
end
try
    str = VBA_summaryMFX(out_group);
    VBA_disp(str,opt)
end
out_group.options.display = [];

% subfunctions

function [m,V,a,b] = MFX_VBupdate(m0,iV0,ms,Vs,a,b,a0,b0,indffx,indIn)
ns = size(ms,2);
n = size(m0,1);
sm = 0;
sv = 0;
wsm = 0;
sP = 0;
indrfx = setdiff(1:n,indffx);
indrfx = intersect(indrfx,indIn);
indffx = intersect(indffx,indIn);
iQ = diag(a(indrfx)./b(indrfx));
for i=1:ns
    % RFX
    sm = sm + ms(indrfx,i);
    e = ms(indrfx,i)-m0(indrfx);
    sv = sv + e.^2 + diag(Vs{i}(indrfx,indrfx));
    % FFX
    tmp = VBA_inv(Vs{i});
    wsm = wsm + tmp*ms(:,i);
    sP = sP + tmp;
end
% RFX
V = zeros(n,n);
m = m0;
V(indrfx,indrfx) = VBA_inv(iV0(indrfx,indrfx)+ns*iQ);
m(indrfx) = V(indrfx,indrfx)*(iV0(indrfx,indrfx)*m0(indrfx)+iQ*sm);
a(indrfx) = a0(indrfx) + 0.5*ns;
% b(indrfx) = b0(indrfx) + 0.5*(sv(indrfx)+ns*diag(V(indrfx,indrfx)));
% fix: do not index because 'sv' is by definition updated only for the rfx
%      parameters
b(indrfx) = b0(indrfx) + 0.5*(sv+ns*diag(V(indrfx,indrfx))); % do not index sv b

% FFX
if ~isempty(indffx)
    tmp = VBA_inv(sP);
    V(indffx,indffx) = tmp(indffx,indffx);
    m(indffx) = V(indffx,indffx)*wsm(indffx);
end



function [F] = MFX_F(p_sub,o_sub,p_group,priors_group,dim,ind)
% free energy computation
F = 0;
ns = length(p_sub);
for i=1:ns
    F = F + o_sub{i}.F;
end
if dim.n_phi > 0
    F = F + FreeEnergy_var(ns,...
        p_group.muPhi,p_group.SigmaPhi,...
        priors_group.muPhi,priors_group.SigmaPhi,...
        p_group.a_vPhi,p_group.b_vPhi,...
        priors_group.a_vPhi,priors_group.b_vPhi,...
        ind.phi_ffx,ind.phi_in);
end
if dim.n_theta > 0
    F = F + FreeEnergy_var(ns,...
        p_group.muTheta,p_group.SigmaTheta,...
        priors_group.muTheta,priors_group.SigmaTheta,...
        p_group.a_vTheta,p_group.b_vTheta,...
        priors_group.a_vTheta,priors_group.b_vTheta,...
        ind.theta_ffx,ind.theta_in);
end
if dim.n > 0
    F = F + FreeEnergy_var(ns,...
        p_group.muX0,p_group.SigmaX0,...
        priors_group.muX0,priors_group.SigmaX0,...
        p_group.a_vX0,p_group.b_vX0,...
        priors_group.a_vX0,priors_group.b_vX0,...
        ind.x0_ffx,ind.x0_in);
end


function F = FreeEnergy_var(ns,mu,V,mu0,V0,a,b,a0,b0,indffx,indIn)
% group-level variable-specific free energy correction term
n = length(mu);
indrfx = setdiff(1:n,indffx);
indrfx = intersect(indrfx,indIn);
n = length(indrfx);
e = mu(indrfx) - mu0(indrfx);
V = V(indrfx,indrfx);
V0 = V0(indrfx,indrfx);
a = a(indrfx);
b = b(indrfx);
a0 = a0(indrfx);
b0 = b0(indrfx);
iv0 = VBA_inv(V0);
F = -0.5*ns*sum(log(a./b)) ...
    + sum((a0+0.5*ns-1).*(psi(a)-log(b))) ...
    - sum((0.5*ns*diag(V)+b0).*a./b) ...
    + sum(a0.*log(b0) + gammaln(b0)) ...
    - 0.5*n*log(2*pi) ...
    - 0.5*VBA_logDet(V0) ...
    - 0.5*e'*iv0*e ...
    - 0.5*trace(iv0*V) ...
    + sum(VBA_entropy('Gamma',a,1./b)) + VBA_entropy('Gaussian',V) ...
    + 0.5*(ns-1).*length(indffx).*log(2*pi);


% check if parameter is fixed or random from group variance hyperparams
% -------------------------------------------------------------------------
function il = isFixedEffect (a, b)
    il = isinf (a) & eq (b, 0);

% initialize within-subject priors
% -------------------------------------------------------------------------
function priors = getSubjectPriors(priors_group, ind, nS)

    % start with fixed effects
    priors.muPhi = priors_group.muPhi;
    priors.SigmaPhi = nS * priors_group.SigmaPhi;
    
    priors.muTheta = priors_group.muTheta;
    priors.SigmaTheta = nS * priors_group.SigmaTheta;

    priors.muX0 = priors_group.muX0;
    priors.SigmaX0 = nS * priors_group.SigmaX0;
    
    % set random effects priors from group
    priors = updateSubjectPriors(priors, priors_group, ind);
    
% update within-subject priors from group posterior
% -------------------------------------------------------------------------
function priors = updateSubjectPriors(priors, posterior_grp, ind)
  
    priors.muPhi(ind.phi_rfx) = posterior_grp.muPhi(ind.phi_rfx);
    priors.SigmaPhi(ind.phi_rfx, ind.phi_rfx) = ...
        diag (posterior_grp.b_vPhi(ind.phi_rfx) ./ posterior_grp.a_vPhi(ind.phi_rfx));

    priors.muTheta(ind.theta_rfx) = posterior_grp.muTheta(ind.theta_rfx);
    priors.SigmaTheta(ind.theta_rfx, ind.theta_rfx) = ...
        diag (posterior_grp.b_vTheta(ind.theta_rfx) ./ posterior_grp.a_vTheta(ind.theta_rfx));

    priors.muX0(ind.x0_rfx) = posterior_grp.muX0(ind.x0_rfx);
    priors.SigmaX0(ind.x0_rfx, ind.x0_rfx) = ...
        diag (posterior_grp.b_vX0(ind.x0_rfx) ./ posterior_grp.a_vX0(ind.x0_rfx));


