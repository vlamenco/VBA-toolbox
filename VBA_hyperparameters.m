function [posterior,out] = VBA_hyperparameters(y,u,f_fname,g_fname,dim,options)
% VB estimation of precision hyperparameters
% [posterior,out] = VBA_hyperparameters(y,u,f_fname,g_fname,dim,options)
% This function embeds the usual VBA model inversion into a further VB
% algorithmic loop, which adjusts precision hyperparameters for evolution
% and observation parameters (as well as initial conditions).
% Note: the ensuing free energy is corrected for the hierarchical extension
% to the generative model.
% IN: [see VBA_NLStateSpaceModel.m] with a unique change:
%   - options.priors: this structure may contain additional scale and shape
%   parameters for precision hyperparameters, namely:
%       .priors.a_phi, priors.b_phi: for observation parameters
%       .priors.a_theta, priors.b_theta: for evolution parameters
% OUT: [see VBA_NLStateSpaceModel.m] with a unique change:
%   - posterior: this structure may contain additional scale and shape
%   parameters for precision hyperparameters, namely:
%       .posterior.a_phi, priors.b_phi: for observation parameters
%       .posterior.a_theta, priors.b_theta: for evolution parameters


posterior = [];
out = [];

% fill in dim structure
try
    dim.n;
    dim.n_theta;
    dim.n_phi;
catch
    disp('Error: VBA_hyperparameters: please provide dimensions of the model!')
    return
end
try
    dim.n_t;
    dim.p;
catch
    dim.n_t = size(y,2);
    dim.p = size(y,1);
end

% specify default options
options.tStart = tic;
% VB display window
if ~isfield(options,'DisplayWin')
    options.DisplayWin = 1;
end
if ~isfield(options,'verbose')
    options.verbose = 1;
end

VBA_disp('--- VBA with hyperparameters adjustment... ---',options)

% Initialize priors
try
    priors = options.priors;
catch
    priors = [];
end
[options.priors,params2update] = VBA_fillInPriors(priors,dim,options.verbose);
nphi = 0;
ntheta = 0;
nx0 = 0;
if dim.n_phi >0
    nphi = length(params2update.phi);
    Qphi = options.priors.SigmaPhi;
    iQphi = VBA_inv(Qphi);
    try
        options.priors.a_phi;
        options.priors.b_phi;
    catch
        options.priors.a_phi = 1;
        options.priors.b_phi = 1;
    end
    Evphi = options.priors.b_phi/options.priors.a_phi;
    options.priors.SigmaPhi = Evphi*Qphi;
    
end
if dim.n_theta >0
    ntheta = length(params2update.theta);
    Qtheta = options.priors.SigmaTheta;
    iQtheta = VBA_inv(Qtheta);
    try
        options.priors.a_theta;
        options.priors.b_theta;
    catch
        options.priors.a_theta = 1;
        options.priors.b_theta = 1;
    end
    Evtheta = options.priors.b_theta/options.priors.a_theta;
    options.priors.SigmaTheta = Evtheta*Qtheta;
end
if dim.n >0
    nx0 = length(params2update.x0);
    Qx0 = options.priors.SigmaX0;
    iQx0 = VBA_inv(Qx0);
    try
        options.priors.a_x0;
        options.priors.b_x0;
    catch
        options.priors.a_x0 = 1;
        options.priors.b_x0 = 1;
    end
    Evx0 = options.priors.b_x0/options.priors.a_x0;
    options.priors.SigmaX0 = Evx0*Qx0;
end

% perform vanilla VBA inversion
VBA_disp(' ',options)
VBA_disp(['VBA hyperparameter adjustment: initialization (using prior hyperparameters)'],options)
[posterior,out] = VBA_NLStateSpaceModel(y,u,f_fname,g_fname,dim,options);
F = out.F;
if nphi>0
    Elp = VBA_psi(options.priors.a_phi) - log(options.priors.b_phi);
    lEp = log(options.priors.a_phi/options.priors.b_phi);
    F = F + 0.5*nphi*(Elp-lEp);
end
if ntheta>0
    Elp = VBA_psi(options.priors.a_theta) - log(options.priors.b_theta);
    lEp = log(options.priors.a_theta/options.priors.b_theta);
    F = F + 0.5*ntheta*(Elp-lEp);
end
if nx0>0
    Elp = VBA_psi(options.priors.a_x0) - log(options.priors.b_x0);
    lEp = log(options.priors.a_x0/options.priors.b_x0);
    F = F + 0.5*nx0*(Elp-lEp);
end

% initialize display
if options.DisplayWin
    hf = figure('color',[1 1 1],'name','VBA hyperparameter adjustment','menubar','none');
    ha(1) = subplot(2,2,1,'parent',hf,'nextplot','add');
    title(ha(1),'F = log p(y|m)')
    plot(ha(1),0,F,'ko')
    set(ha(1),'xlim',[-.2,0.8],'xtick',[])
    xlabel(ha(1),'VBA meta-iterations')
    if nphi >0
        ha(2) = subplot(2,2,2,'parent',hf,'nextplot','add');
        title(ha(2),'PHI')
        EP = options.priors.a_phi/options.priors.b_phi;
        VP = EP/options.priors.b_phi;
        set(ha(2),'xlim',[-.2,0.8],'xtick',[])
        logCI = log(EP+sqrt(VP)) - log(EP);
        plotUncertainTimeSeries(log(EP),logCI.^2,0,ha(2));
        set(ha(2),'ygrid','on','xgrid','off')
        xlabel(ha(2),'VBA meta-iterations')
    end
    if ntheta >0
        ha(3) = subplot(2,2,3,'parent',hf,'nextplot','add');
        title(ha(3),'THETA')
        EP = options.priors.a_theta/options.priors.b_theta;
        VP = EP/options.priors.b_theta;
        set(ha(3),'xlim',[-.2,0.8],'xtick',[])
        logCI = log(EP+sqrt(VP)) - log(EP);
        plotUncertainTimeSeries(log(EP),logCI.^2,0,ha(3));
        set(ha(3),'ygrid','on','xgrid','off')
        xlabel(ha(3),'VBA meta-iterations')
    end
    if nx0 >0
        ha(4) = subplot(2,2,4,'parent',hf,'nextplot','add');
        title(ha(4),'X0')
        EP = options.priors.a_x0/options.priors.b_x0;
        VP = EP/options.priors.b_x0;
        set(ha(4),'xlim',[-.2,0.8],'xtick',[])
        logCI = log(EP+sqrt(VP)) - log(EP);
        plotUncertainTimeSeries(log(EP),logCI.^2,0,ha(4));
        set(ha(4),'ygrid','on','xgrid','off')
        xlabel(ha(4),'VBA meta-iterations')
    end
    drawnow
    getSubplots
end

%--- VB: iterate until convergence... ---%
stop = 0;
it = 1;
while ~stop
    
    % adjust precision hyperparameters
    VBA_disp(['VBA hyperparameter adjustment: iteration #',num2str(it)],options)
    if nphi >0
         posterior.a_phi = options.priors.a_phi + 0.5*nphi;
         Edphi = out.suffStat.dphi'*iQphi*out.suffStat.dphi + trace(iQphi*posterior.SigmaPhi);
         posterior.b_phi = options.priors.b_phi + 0.5*Edphi;
    end
    if ntheta >0
         posterior.a_theta = options.priors.a_theta + 0.5*ntheta;
         Edtheta = out.suffStat.dtheta'*iQtheta*out.suffStat.dtheta + trace(iQtheta*posterior.SigmaTheta);
         posterior.b_theta = options.priors.b_theta + 0.5*Edtheta;
    end
    if nx0 >0
         posterior.a_x0 = options.priors.a_x0 + 0.5*nx0;
         Edx0 = out.suffStat.dx0'*iQx0*out.suffStat.dx0 + trace(iQx0*posterior.SigmaX0);
         posterior.b_x0 = options.priors.b_x0 + 0.5*Edx0;
    end
    
    % correct Free Energy
    F(it+1) = out.F;
    if nphi >0
        cF = deltaF(posterior.a_phi,options.priors.a_phi,posterior.b_phi,options.priors.b_phi,nphi);
        F(it+1) = F(it+1) + cF;
    end
    if ntheta >0
        cF = deltaF(posterior.a_theta,options.priors.a_theta,posterior.b_theta,options.priors.b_theta,ntheta);
        F(it+1) = F(it+1) + cF;
    end
    if nx0 >0
        cF = deltaF(posterior.a_x0,options.priors.a_x0,posterior.b_x0,options.priors.b_x0,nx0);
        F(it+1) = F(it+1) + cF;
    end
    
    % display progress
    if options.DisplayWin
        plot(ha(1),it,F(it+1),'ko')
        set(ha(1),'xlim',[-.2,it+0.8],'xtick',[])
        if nphi >0
            EP = posterior.a_phi/posterior.b_phi;
            VP = EP/posterior.b_phi;
            set(ha(2),'xlim',[-.2,it+0.8],'xtick',[])
            logCI = log(EP+sqrt(VP)) - log(EP);
            plotUncertainTimeSeries(log(EP),logCI.^2,it,ha(2));
            set(ha(2),'ygrid','on','xgrid','off')
        end
        if ntheta >0
            EP = posterior.a_theta/posterior.b_theta;
            VP = EP/posterior.b_theta;
            set(ha(3),'xlim',[-.2,it+0.8],'xtick',[])
            logCI = log(EP+sqrt(VP)) - log(EP);
            plotUncertainTimeSeries(log(EP),logCI.^2,it,ha(3));
            set(ha(3),'ygrid','on','xgrid','off')
        end
        if nx0 >0
            EP = posterior.a_x0/posterior.b_x0;
            VP = EP/posterior.b_x0;
            set(ha(4),'xlim',[-.2,it+0.8],'xtick',[])
            logCI = log(EP+sqrt(VP)) - log(EP);
            plotUncertainTimeSeries(log(EP),logCI.^2,it,ha(4));
            set(ha(4),'ygrid','on','xgrid','off')
        end
        drawnow
    end
    
    % re-specify priors for vanilla VBA inversion
    if nphi >0
        Evphi = posterior.b_phi/posterior.a_phi;
        options.priors.SigmaPhi = Evphi*Qphi;
    end
    if ntheta>0
        Evtheta = posterior.b_theta/posterior.a_theta;
        options.priors.SigmaTheta = Evtheta*Qtheta;
    end
    if nx0>0
        Evx0 = posterior.b_x0/posterior.a_x0;
        options.priors.SigmaX0 = Evx0*Qx0;
    end
        
    % perform vanilla VBA inversion
    in.posterior = posterior;
    in.out = out;
    in.out.options.priors = options.priors;
    [posterior,out] = VBA_NLStateSpaceModel(y,u,f_fname,g_fname,dim,options,in);
   
    % check convergence
    dF = F(it+1) - F(it);
    if abs(dF) <= out.options.TolFun || it >= out.options.MaxIter
        stop = 1;
    end
    it = it +1;
    
end

% store corrected Free Energy
F(it) = out.F;
if nphi >0
    cF = deltaF(posterior.a_phi,options.priors.a_phi,posterior.b_phi,options.priors.b_phi,nphi);
    F(it) = F(it) + cF;
end
if ntheta >0
    cF = deltaF(posterior.a_theta,options.priors.a_theta,posterior.b_theta,options.priors.b_theta,ntheta);
    F(it) = F(it) + cF;
end
if nx0 >0
    cF = deltaF(posterior.a_x0,options.priors.a_x0,posterior.b_x0,options.priors.b_x0,nx0);
    F(it) = F(it) + cF;
end
out.F = F(it);

% wrap-up
out.options.tStart = options.tStart;
out.dt = toc(options.tStart);

VBA_disp(' ',out.options)
VBA_disp('--- VBA with hyperparameters adjustment: done. ---',options)
if options.DisplayWin
    getSubplots
end

% subfunctions
function dF = deltaF(a,a0,b,b0,n)
% dF = a0*log(b0) - a*log(b) - (gammaln(a0)-gammaln(a)) + a*(1-b0/b);
m1 = a/b;
v1 = m1/b;
m2 = a0/b0;
v2 = m2/b0;
[DKL] = VBA_KL(m1,v1,m2,v2,'Gamma');
Elp = VBA_psi(a) - log(b);
% dF = 0.5*n*Elp - DKL;
lEp = log(a/b);
dF = 0.5*n*(Elp-lEp) - DKL;
